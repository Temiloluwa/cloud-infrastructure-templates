## Introduction

Amazon S3 buckets can be configured to emit event messages in response to actions. Object creation and removal are sample events for which S3 publishes messages. The entire list is found [here](https://docs.aws.amazon.com/AmazonS3/latest/userguide/NotificationHowTo.html). This post describes how to configure custom email notifications for S3 events using CloudFormation. The solution deployed by the CloudFormation template is summarised as: S3 events are consumed by a  Lambda function then custom notification emails are sent by the function using Simple Email Service (SES). Although Simple Notification Service (SNS) comes first to mind for notifications, it lacks the facility to send out customised emails. 

## Challenge

This solution is simple to implement in the Amazon Console but becomes complicated when automated with CloudFormation. The three main resources to be created by CloudFormation are:

1. The s3 bucket that emits notification events
2. The lambda function that sends emails with SES
3. A custom resource that changes the S3 bucket's configurations, granting rights to the Lambda function for consumption of bucket notification events. 

If the notification configurations are applied directly to the S3 bucket resource, a circular dependency occurs. This article clearly elucidates the problem: [here](https://aws.amazon.com/blogs/mt/resolving-circular-dependency-in-provisioning-of-amazon-s3-buckets-with-aws-lambda-event-notifications/).

## Approach

The problem is tackled by first creating each of the above mentioned resources in isolation. Next, a custom resource applies the notification configurations to the bucket with a Lambda function.

Custom resources allow developers to implement features that are not natively supported by CloudFormation. Custom resources basically make API calls to perform CRUD operations of AWS resources. There are libraries written in python and javascript that make constructing these API calls easier.

## Implementation

Let's walk through a CloudFormation template that creates resources for sending emails when files are uploaded to an S3 bucket. 

The template begins by defining the following parameters:
- `BucketName` for naming the S3 bucket
- `NotificationLambdaFnName` for naming the Lambda function that sends emails
- `CustomLambdaFnName` for naming the Lambda function that is executed by the custom resource
- `SenderEmail` the email addrress that sends out the notification emails
- `RecipientEmail` the email address that receives the notification emails
- `AWSREGION` the aws region the email addresses are registered to in SES

```yaml
AWSTemplateFormatVersion: 2010-09-09
Description: Send email notifications when files are uploaded to an s3 bucket

Parameters:

  BucketName:
    Type: String
    Default: bkt-notify-email-1001

  NotificationLambdaFnName:
    Type: String
    Default: fn-notify-email-1001

  CustomLambdaFnName:
    Type: String
    Default: custom-fn-notify-email-1001

  # modify value to a verified SES email
  SenderEmail:
    Type: String
    Default: fromsomeone@gmail.com

  # modify value to a verified SES email
  RecipientEmail:
    Type: String
    Default: tosomeone@gmail.com

  AWSREGION:
    Type: String
    Default: us-east-1

```

The rest of the template consists of resources. The first four resources are the S3 bucket (`S3Bucket`), the lambda function that sends out emails (`NotificationFunction`), the lambda function that applies notification configurations to the s3 bucket (`ApplyS3Notification`), and the custom resource (`ApplyNotification`).

The codes for the lambda functions are written in python.

``` yaml

Resources:

  S3Bucket:
    Type: 'AWS::S3::Bucket'
    Properties:
      AccessControl: Private
      BucketName: !Ref BucketName

  # lambda function that sends emails
  NotificationFunction: 
    Type: AWS::Lambda::Function
    Properties:
      Description: Function that sends email notifications for s3 bucket file uploads
      FunctionName: !Ref NotificationLambdaFnName
      Environment:
        Variables:
          sender: !Ref SenderEmail
          recipient: !Ref RecipientEmail
          awsregion: !Ref AWSREGION
      Handler: email_sender.handler
      Runtime: python3.8
      Role: !GetAtt 'NotificationFunctionRole.Arn'
      Timeout: 240
      Code: lambda-email/

  # lambda function for custom resource
  ApplyS3Notification:
    Type: AWS::Lambda::Function
    Properties:
      Description: Function that attaches creates S3 notification config
      FunctionName: !Ref CustomLambdaFnName
      Handler: lambda_fn.handler
      Runtime: python3.8
      Role: !GetAtt 'ApplyS3NotificationFuncRole.Arn'
      Timeout: 240
      Code: lambda-notify/


  # Custom resource to apply notification configuration to s3 bucket
  ApplyNotification:
    Type: Custom::ApplyNotification
    Properties:
      ServiceToken: !GetAtt ApplyS3Notification.Arn
      S3BucketName: !Ref BucketName
      FunctionARN: !GetAtt 'NotificationFunction.Arn'
    
    DependsOn:
      - S3Bucket

```

Yes you keen observer! I know the roles referenced by the `!Get Attr` functions are missing. They are found in the code snippet below which defines the following resources:
-  `NotificationFunctionRole`: A role assumed by the lambda function for sending emails using SES. The role has the AWS managed `AWSLambdaBasicExecutionRole` and an attached SES policy for sending emails.
- `ApplyS3NotificationFuncRole`: This role is assumed by the custom resources and permits it to apply notification configuration changes to the S3 bucket. It has an AWS managed `AWSLambdaBasicExecutionRole` and an attached policy with the `s3:PutBucketNotification` action.
- `S3ToLambdaPermission` is a permission resource that is applied to the lambda function that sends out emails. It permits it to consume events from the S3 bucket.

``` yaml
  # Role for lambda function that sends email. Requires SES policy
  NotificationFunctionRole:
    Type: AWS::IAM::Role
    Properties:
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service: lambda.amazonaws.com
            Action: sts:AssumeRole
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
      Path: /
      Policies:
        - PolicyName: PolicySendEmailWithSES
          PolicyDocument:
            Version: '2012-10-17'
            Statement:
              - Sid: SendEmailswithSES
                Effect: Allow
                Action:
                  - ses:SendEmail
                  - ses:SendRawEmail
                Resource: '*'

  # Role that allows custom resource lambda function to apply notification configurations to s3 bucket
  ApplyS3NotificationFuncRole:
    Type: AWS::IAM::Role
    Properties:
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service: lambda.amazonaws.com
            Action: sts:AssumeRole
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
      Path: /
      Policies:
        - PolicyName: S3BucketNotificationPolicy
          PolicyDocument:
            Version: '2012-10-17'
            Statement:
              - Sid: AllowBucketNotification
                Effect: Allow
                Action: s3:PutBucketNotification
                Resource:
                  - !Sub 'arn:aws:s3:::${S3Bucket}'
                  - !Sub 'arn:aws:s3:::${S3Bucket}/*'
  

  # permission applied to lambda function to allow it to read s3 notifications
  S3ToLambdaPermission:
    Type: AWS::Lambda::Permission
    Properties:
      Action: lambda:invokeFunction
      SourceAccount: !Ref AWS::AccountId
      FunctionName: !Ref NotificationLambdaFnName
      SourceArn: !GetAtt 'S3Bucket.Arn'
      Principal: s3.amazonaws.com
    
    DependsOn:
      - NotificationFunction

```

## Custom Resource

Our custom resource invokes a lambda function that applies notification configurations to the s3 bucket. The lambda function's ARN serves as the service token for the custom resource. Two parameters are defined and passed on to the lambda function: `S3BucketName` and `FunctionARN`.

The lamdba function executes a python script that uses the `boto3` library to apply the notification configurations to the s3 bucket. The API calls to CloudFormation are enabled by the custom resource python library called [Custom Resource Helper](https://github.com/aws-cloudformation/custom-resource-helper).

## Sending Emails with Lambda and SES

The second lambda function sends out emails using SES when files are uploaded to the S3 bucket. The sender and recepient emails must already be verified in SES. If your SES is no more in Sandbox mode, then only the sender email address needs to be verified.

The email addresses and their associated AWS region in which they were verified in SES are passed as environmental variables to the lambda function.

## Template Deployment

An s3 bucket to which the CloudFormation template will be deployed is required. 
The bucket will exist if you have created CloudFormation stacks in the past.

Next, python dependencies must be downloaded to the target folder of the lambda function. In our use case, the `Custom Resource Helper` library is downloaded to the customer resource lambda function's directory.

The `aws cloudformation package` command is then run to package the template and lambda functions and generate an output template file. The CloudFormation template's name, the CloudFormation s3 bucket name, and the output template file name are included in the command.

Finally, the `aws cloudformation deploy` command deploys the generated output template file.

The following code snippet displays the deployment steps.

```sh
# create s3 bucket to deploy cloud formation template
aws s3 mb "s3://$bucket" --region $region

# install python dependencies
pip install -r lambda-notify/requirements.txt --target lambda-notify

# package template
aws cloudformation package \
    --template-file $template \
    --s3-bucket $bucket\
    --output-template-file $output

# deploy template
aws cloudformation deploy \
    --capabilities CAPABILITY_IAM \
    --template-file $output \
    --stack-name $stackname

```

## Testing

The status of the stack deployment can be monitored on CloudFormation in the AWS console or the command line. Test the deployment by uploading a file to the s3 bucket and confirming a notification email is received by the recipient.


## Conclusion

This article explains how to configure a lambda Function to send out custom emails based on event changes on an s3 bucket. The process is automated using a CloudFormation template. To access the complete codebase for this solution, clone the following Github Repo: [here](https://github.com/Temiloluwa/cloud-infrastructure-templates.git).

## References
1. [Resolving circular dependency in provisioning of Amazon S3 buckets with AWS Lambda event notifications](https://aws.amazon.com/blogs/mt/resolving-circular-dependency-in-provisioning-of-amazon-s3-buckets-with-aws-lambda-event-notifications/)
2. [AWS CloudFormation custom resource creation with Python, AWS Lambda, and crhelper](https://aws.amazon.com/blogs/infrastructure-and-automation/aws-cloudformation-custom-resource-creation-with-python-aws-lambda-and-crhelper/)
3. [Custom Resource Helper](https://github.com/aws-cloudformation/custom-resource-helper)
4. [How do I send email using Lambda and Amazon SES](https://aws.amazon.com/premiumsupport/knowledge-center/lambda-send-email-ses/)