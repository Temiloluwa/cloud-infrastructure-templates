# Description
Send S3 notifications by email using SES using CloudFormation

# Resources

1. S3 bucket
2. Lambda function for sending emails
3. Lambda Policy or permission to invoke s3
4. Custom Lambda (to apply permission to first Lambda function)
5. SES for registering emails
6. Lambda Basic Execution Role that also has permission to SES


