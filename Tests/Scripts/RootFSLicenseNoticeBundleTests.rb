#!/usr/bin/env ruby

require "digest"
require "minitest/autorun"
require "pathname"
require "tmpdir"
require_relative "../../Scripts/prepare-rootfs-license-notice-bundle"

class RootFSLicenseNoticeBundleTests < Minitest::Test
  def test_reads_and_verifies_cached_remote_payload
    Dir.mktmpdir("rootfs-notice-cache") do |directory|
      cache = Pathname(directory)
      contents = "pinned license text\n"
      cache.join("license.txt").binwrite(contents)
      payload = remote_payload(contents)

      actual =
        RootFSLicenseNoticeBundle.fetch_remote_payload(
          payload,
          cache,
          false
        )

      assert_equal contents, actual
    end
  end

  def test_rejects_cached_remote_payload_digest_drift
    Dir.mktmpdir("rootfs-notice-cache") do |directory|
      cache = Pathname(directory)
      cache.join("license.txt").binwrite("changed\n")
      payload = remote_payload("expected\n")

      error = assert_raises(
        RootFSLicenseNoticeBundle::BundleError
      ) do
        RootFSLicenseNoticeBundle.fetch_remote_payload(
          payload,
          cache,
          false
        )
      end

      assert_includes error.message, "byte count mismatch"
    end
  end

  def test_streams_https_response_instead_of_using_request_return_value
    contents = "downloaded license\n"
    response = Net::HTTPOK.new("1.1", "200", "OK")
    response["content-length"] = contents.bytesize.to_s
    response.define_singleton_method(:read_body) do |&block|
      block.call(contents)
    end
    http = Object.new
    http.define_singleton_method(:request) do |_request, &block|
      block.call(response)
      response
    end

    with_stubbed_http_start(http) do
      actual =
        RootFSLicenseNoticeBundle.download_https(
          "https://example.invalid/license.txt",
          1_024
        )

      assert_equal contents, actual
    end
  end

  def test_retries_next_url_after_http_connection_exception
    contents = "fallback license\n"
    response = Net::HTTPOK.new("1.1", "200", "OK")
    response["content-length"] = contents.bytesize.to_s
    response.define_singleton_method(:read_body) do |&block|
      block.call(contents)
    end
    http = Object.new
    http.define_singleton_method(:request) do |_request, &block|
      block.call(response)
      response
    end
    forbidden = Net::HTTPForbidden.new("1.1", "403", "Forbidden")
    connection_error =
      Net::HTTPClientException.new("proxy rejected CONNECT", forbidden)
    starts = 0
    original = Net::HTTP.method(:start)
    Net::HTTP.singleton_class.send(:define_method, :start) do |*_args, **_options, &block|
      starts += 1
      raise connection_error if starts == 1

      block.call(http)
    end
    payload = remote_payload(contents)
    payload["retrievalURLs"] = [
      "https://first.invalid/license.txt",
      "https://second.invalid/license.txt"
    ]

    actual =
      RootFSLicenseNoticeBundle.fetch_remote_payload(
        payload,
        nil,
        false
      )

    assert_equal contents, actual
    assert_equal 2, starts
  ensure
    Net::HTTP.singleton_class.send(:define_method, :start, original) if original
  end

  def test_materialize_and_verify_rejects_path_drift
    Dir.mktmpdir("rootfs-notice-output") do |directory|
      parent = Pathname(directory)
      output = parent.join("bundle")
      payloads = {
        "licenses/MIT.txt" => "license\n",
        "NOTICE-CANDIDATES.md" => "notice\n"
      }
      RootFSLicenseNoticeBundle.materialize(output, payloads)
      RootFSLicenseNoticeBundle.verify_bundle(output, payloads)

      output.join("extra").binwrite("unexpected\n")
      error = assert_raises(
        RootFSLicenseNoticeBundle::BundleError
      ) do
        RootFSLicenseNoticeBundle.verify_bundle(output, payloads)
      end

      assert_includes error.message, "path/type set"
    end
  end

  def test_verify_rejects_symlink
    Dir.mktmpdir("rootfs-notice-output") do |directory|
      root = Pathname(directory)
      root.join("payload").make_symlink(root.join("missing"))

      error = assert_raises(
        RootFSLicenseNoticeBundle::BundleError
      ) do
        RootFSLicenseNoticeBundle.actual_path_types(root)
      end

      assert_includes error.message, "symlink"
    end
  end

  private

  def remote_payload(contents)
    {
      "cacheKey" => "license.txt",
      "outputPath" => "licenses/license.txt",
      "byteCount" => contents.bytesize,
      "sha256" => Digest::SHA256.hexdigest(contents),
      "retrievalURLs" => ["https://example.invalid/license.txt"]
    }
  end

  def with_stubbed_http_start(http)
    original = Net::HTTP.method(:start)
    Net::HTTP.singleton_class.send(:define_method, :start) do |*_args, **_options, &block|
      block.call(http)
    end
    yield
  ensure
    Net::HTTP.singleton_class.send(:define_method, :start, original)
  end
end
