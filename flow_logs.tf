###############################################################################
# VPC Flow Logs -> CloudWatch Logs
###############################################################################

data "aws_caller_identity" "current" {
  count = var.enable_flow_logs ? 1 : 0
}

resource "aws_cloudwatch_log_group" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  #checkov:skip=CKV_AWS_158:KMS encryption is opt-in through var.flow_logs_kms_key_arn (log groups are encrypted at rest by AWS by default).
  name              = "/aws/vpc/${local.name_prefix}/flow-logs"
  retention_in_days = var.flow_logs_retention_days
  kms_key_id        = var.flow_logs_kms_key_arn

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-flow-logs" })
}

resource "aws_iam_role" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name_prefix = substr("${local.name_prefix}-flowlogs-", 0, 38)
  description = "Allows VPC Flow Logs for ${local.name_prefix} to publish to CloudWatch Logs"

  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{
      Sid       = "VpcFlowLogsAssumeRole"
      Effect    = "Allow"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
      Action    = "sts:AssumeRole"
      # Confused-deputy protection: only this account's flow logs may assume the role.
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current[0].account_id }
      }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name = "publish-flow-logs"
  role = aws_iam_role.flow_logs[0].id

  # Least privilege: scoped to the single log group created above.
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{
      Sid    = "PublishFlowLogs"
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogStreams",
      ]
      Resource = [
        aws_cloudwatch_log_group.flow_logs[0].arn,
        "${aws_cloudwatch_log_group.flow_logs[0].arn}:*",
      ]
    }]
  })
}

resource "aws_flow_log" "this" {
  count = var.enable_flow_logs ? 1 : 0

  vpc_id                   = aws_vpc.this.id
  traffic_type             = var.flow_logs_traffic_type
  log_destination_type     = "cloud-watch-logs"
  log_destination          = aws_cloudwatch_log_group.flow_logs[0].arn
  iam_role_arn             = aws_iam_role.flow_logs[0].arn
  max_aggregation_interval = 60

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-flow-log" })
}
