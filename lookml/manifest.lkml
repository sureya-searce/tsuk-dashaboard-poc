# Project-wide constants — retarget the whole LookML project in one place.
# sql_table_name everywhere uses @{gcp_project}.@{ds_*}.<table>.

constant: gcp_project {
  value: "infraappsandbox"
  export: override_optional
}

# Gold datasets (ownership boundaries).
constant: ds_core        { value: "searce_poc_core" }        # shared governed
constant: ds_finance     { value: "searce_poc_finance" }     # Finance-owned
constant: ds_supplychain { value: "searce_poc_supplychain" } # Supply-Chain-owned
