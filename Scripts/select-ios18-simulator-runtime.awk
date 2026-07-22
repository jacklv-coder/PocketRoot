# `simctl list runtimes available` output varies across Xcode releases. Locate
# the stable runtime identifier instead of assuming it is the final field.
/^iOS 18[.]/ {
    for (field = 1; field <= NF; field++) {
        if (runtime_id == "" &&
            $field ~ /^com[.]apple[.]CoreSimulator[.]SimRuntime[.]iOS-18-[0-9-]+$/) {
            runtime_id = $field
        }
    }
}

END {
    if (runtime_id != "") {
        print runtime_id
    }
}
