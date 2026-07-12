data "aws_caller_identity" "current" {}

check "supported_partition" {
  assert {
    condition     = data.aws_caller_identity.current.account_id != ""
    error_message = "AWS credentials are missing or invalid. Refresh the KodeKloud playground credentials before applying."
  }
}

