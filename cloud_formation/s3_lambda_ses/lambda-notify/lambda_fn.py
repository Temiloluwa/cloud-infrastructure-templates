import json
import logging
import boto3
from crhelper import CfnResource

logger = logging.getLogger(__name__)
helper = CfnResource(json_logging=False, log_level='DEBUG', boto_level='CRITICAL', sleep_on_delete=120, ssl_verify=None)

@helper.create
@helper.update
def handler(event, context):
  logger.info("Creating or Updating")
  bucket_name = event['ResourceProperties']['S3BucketName']
  lambda_arn = event['ResourceProperties']['FunctionARN']
  s3 = boto3.resource('s3')
  bucket_notification = s3.BucketNotification(bucket_name)

  response = bucket_notification.put(
      NotificationConfiguration={'LambdaFunctionConfigurations': [
      {
          'Id': 'object-create-permission',
          'LambdaFunctionArn': lambda_arn,
          'Events': [
              's3:ObjectCreated:*'],
      }
  ]})

  if response:
    logger.info(f"Created or Updated, {json.dumps(response)}")

  return response

@helper.delete
def delete(event, context):
  logger.info("Deleted")

def handler(event, context):
  helper(event, context)