#!/bin/sh
aws cloudformation package \
    --template-file template.yaml \
    --s3-bucket cf-templates-1sj9kzph2p7xj-us-east-1 \
    --output-template-file template-packaged.yaml

aws cloudformation deploy \
    --capabilities CAPABILITY_IAM \
    --template-file /Users/t.adeoti/Documents/aws/cloudformation/s3-notifications/final/s3_lambda_ses/template-packaged.yaml \
    --stack-name ses-s3-notification-stack-0070