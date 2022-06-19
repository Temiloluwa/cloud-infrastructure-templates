## Introduction

Amazon S3 buckets can be configured to emit event messages in response to actions. Object creation and removal are sample events for which S3 publishes messages. The entire list is found [here](https://docs.aws.amazon.com/AmazonS3/latest/userguide/NotificationHowTo.html). This post describes how to configure custom email notifications for S3 events using CloudFormation. The solution deployed by the CloudFormation template is summarised as: S3 events are consumed by a  Lambda function then custom notification emails are sent by the function using Simple Email Service (SES). Although Simple Notification Service (SNS) comes first to mind for notifications, it lacks the facility to send out customised emails. 

## Challenge

This solution is simple to implement in the Amazon Console but becomes complicated when automated with CloudFormation. The three main resources to be created by CloudFormation are:

1. The s3 bucket that emits notification events
2. The lambda function that sends emails with SES
3. A permission resource that grants rights to the Lambda function to consume bucket notification events. 

If the permission is applied directly to the S3 bucket resource, a circular dependency occurs. This article clearly elucidates the problem: [here](https://aws.amazon.com/blogs/mt/resolving-circular-dependency-in-provisioning-of-amazon-s3-buckets-with-aws-lambda-event-notifications/).

## Approach

The problem is tackled by first creating each of the above mentioned resources in isolation, then making custom resource with a Lambda function that applies the S3 notification configurations to the bucket.

Custom resources allow developers to implement features that are not natively supported by Cloud formation. Custom resources basically make API calls to perform CRUD operations of AWS resources. There are libraries written python and javascript that make constructing these API calls easier.

## Implementation

Let's walk through a Cloud formation template that creates resources for sending emails when files are uploaded to an S3 bucket. 

The template begins by defining parameters for naming the S3 bucket, the Lambda function that sends emails, and another Lambda function that is executed by the custom resource.

```yaml
AWSTemplateFormatVersion: 2010-09-09
Description: Send emails notifications when files are uploaded to an s3 bucket

Parameters:

  BucketName:
    Type: String
    Default: bkt-notify-email

  NotificationLambdaFnName:
    Type: String
    Default: fn-notify-email

  CustomLambdaFnName:
    Type: String
    Default: custom-fn-notify-email
```

The rest of the template consists of resources. The first four resources are the S3 bucket (`S3Bucket`), the lambda function that sends out emails (`NotificationFunction`), the lambda function that applies notification configurations to the s3 bucket (`ApplyS3Notification`), and the custom resource (`ApplyNotification`).

The codes for the lambda functions are written in python. The codes will be explained later in the article.

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
      Description: Sends email for s3 bucket file uploads
      FunctionName: !Ref NotificationLambdaFnName
      Handler: email_sender.handler
      Runtime: python3.8
      Role: !GetAtt 'NotificationFunctionRole.Arn'
      Timeout: 240
      Code: lambda-email/
  
  # lambda function ran by the custom function
  ApplyS3Notification:
    Type: AWS::Lambda::Function
    Properties:
      Description: Attaches permissions to the S3 bucket
      FunctionName: !Ref CustomLambdaFnName
      Handler: lambda_fn.handler
      Runtime: python3.8
      Role: !GetAtt 'ApplyS3NotificationFuncRole.Arn'
      Timeout: 240
      Code: lambda-notify/


  # Custom Resource
  ApplyNotification:
    Type: Custom::ApplyNotification
    Properties:
      ServiceToken: !GetAtt ApplyS3Notification.Arn
      S3BucketName: !Ref BucketName
      FunctionARN: !GetAtt 'NotificationFunction.Arn'
    
    DependsOn:
      - S3Bucket

```

Yes you keen observer! I know the roles referenced by the `!Get Attr` functions are missing. They are defined in the code snippets below. The resource that permits the Lambda function to consume the events is also defined.

``` yaml
# Role for lambda function that sends email. Includes SES 
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

  # Role that grants lambda fn to apply notification config
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
  

  # permits lambda function to consume s3 events
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
