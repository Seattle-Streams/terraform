variable "runtime" {}
variable "timeout" {}

# data "archive_file" "twilio_zip" {
#   type        = "zip"
#   output_path = "twilio_function.zip"
#   source_file = "TwilioIntegration.py"
# }

data "archive_file" "youtube_zip" {
  type        = "zip"
  source_file = "YoutubeIntegration.py"
  output_path = "youtube_function.zip"
}

data "aws_iam_policy_document" "lambda_policy" {
  statement {
    effect = "Allow"

    principals {
      identifiers = ["lambda.amazonaws.com"]
      type        = "Service"
    }

    actions = ["sts:AssumeRole", ]
  }
}

resource "aws_iam_role" "iam_lambda_execution_role" {
  name               = "lambda_execution_role"
  assume_role_policy = "${data.aws_iam_policy_document.lambda_policy.json}"
}

# Lambdas
resource "aws_lambda_function" "twilio_lambda" {
  function_name = "twilio_lambda"

  s3_bucket = "process-messages-builds"
  s3_key    = "twilio_lambda.zip"

  role    = "${aws_iam_role.iam_lambda_execution_role.arn}"
  handler = "TwilioIntegration.ProcessMessage"
  runtime = "${var.runtime}"
  timeout = "${var.timeout}"
  environment {
    variables = {
      SQS_URL = "${aws_sqs_queue.sms_queue.id}"
    }
  }
  depends_on = [
    "aws_iam_role_policy_attachment.lambda_logs",
  ]
}

resource "aws_lambda_function" "youtube_lambda" {
  function_name = "youtube_lambda"

  filename = "youtube_lambda.zip"
  #   s3_bucket = "process-messages-builds"
  #   s3_key    = "youtube_lambda.zip"

  role    = "${aws_iam_role.iam_lambda_execution_role.arn}"
  handler = "YoutubeIntegration.ProcessMessage"
  runtime = "${var.runtime}"
  timeout = "${var.timeout}"
  depends_on = [
    "aws_iam_role_policy_attachment.lambda_logs",
  ]
}


####################################################################################################
##########################         Lambda Policies         #########################################
####################################################################################################

# This is to manage the CloudWatch Log Group for the Lambda Function.
resource "aws_cloudwatch_log_group" "twilio_lambda_log_group" {
  name              = "/aws/lambda/${aws_lambda_function.twilio_lambda.function_name}"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "youtube_lambda_log_group" {
  name              = "/aws/lambda/${aws_lambda_function.youtube_lambda.function_name}"
  retention_in_days = 30
}

# See also the following AWS managed policy: AWSLambdaBasicExecutionRole
resource "aws_iam_policy" "lambda_logging" {
  name        = "lambda_logging"
  description = "IAM policy for logging from a lambda"

  policy = "${data.aws_iam_policy_document.log_policy.json}"
}

data "aws_iam_policy_document" "log_policy" {
  statement {
    effect = "Allow"

    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:*:*:*"]
  }
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = "${aws_iam_role.iam_lambda_execution_role.name}"
  policy_arn = "${aws_iam_policy.lambda_logging.arn}"
}

resource "aws_iam_policy" "lambda_sending" {
  name        = "lambda_sending"
  description = "IAM policy for sending to sqs from a lambda"

  policy = "${data.aws_iam_policy_document.lambda_send_policy.json}"
}

resource "aws_iam_policy" "lambda_receiving" {
  name        = "lambda_receiving"
  description = "IAM policy for lambda receiving messages from sqs"

  policy = "${data.aws_iam_policy_document.lambda_receive_policy.json}"
}

# remember to decouple send and receive
data "aws_iam_policy_document" "lambda_send_policy" {
  statement {
    effect = "Allow"
    actions = [
      "sqs:SendMessage"
    ]
    resources = [
      "${aws_sqs_queue.sms_queue.arn}"
    ]
  }
}

data "aws_iam_policy_document" "lambda_receive_policy" {
  statement {
    effect = "Allow"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes"
    ]
    resources = [
      "${aws_sqs_queue.sms_queue.arn}"
    ]
  }
}

resource "aws_iam_role_policy_attachment" "lambda_send" {
  role       = "${aws_iam_role.iam_lambda_execution_role.name}"
  policy_arn = "${aws_iam_policy.lambda_sending.arn}"
}

resource "aws_iam_role_policy_attachment" "lambda_receive" {
  role       = "${aws_iam_role.iam_lambda_execution_role.name}"
  policy_arn = "${aws_iam_policy.lambda_receiving.arn}"
}

####################################################################################################
##########################          S3 Resources           #########################################
####################################################################################################

resource "aws_s3_bucket" "process-messages-builds" {
  bucket = "process-messages-builds"
  acl    = "private"

  tags = {
    Name        = "process-messages-builds"
    Environment = "Prod"
  }
}

####################################################################################################
##########################          SQS Resources          #########################################
####################################################################################################

resource "aws_sqs_queue" "sms_queue" {
  name             = "sms_queue"
  delay_seconds    = 0
  max_message_size = 2048
  # at least 6 times the timeout of the lamda receiving messages
  message_retention_seconds = 3600
  receive_wait_time_seconds = 0

  tags = {
    Environment = "production"
  }
}

# https://github.com/flosell/terraform-sqs-lambda-trigger-example/blob/master/trigger.tf
resource "aws_lambda_event_source_mapping" "sqs_message" {
  batch_size       = 1
  event_source_arn = "${aws_sqs_queue.sms_queue.arn}"
  function_name    = "${aws_lambda_function.youtube_lambda.arn}"
  enabled          = true
}
