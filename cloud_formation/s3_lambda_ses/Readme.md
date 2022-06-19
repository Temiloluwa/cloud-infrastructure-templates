# Description
Sends S3 notifications by email using SES

# Requirements
- Sender email address and recipient email addresses that have been verified in SES.

If SES sand-box mode is deactivated, recipient email address requires no verification.
Ensure to replace the default email addresses in the template with the verified addressses.

# Template Deployment
1. Ensure AWS CLI is installed and configured to interact with AWS. Instructions are available [here](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-quickstart.html)
2. Run `deploy.sh` and specifiy the following command line parameters:
    - `-t`: name of template file
    - `-b`: name of s3 bucket to which the packaged cloudformation template will be uploaded
    - `-o`: name of packaged cloudformation template file
    - `-s`: cloudformation stack name
    - `-r`: aws region

    Example: 
    ```sh
    sh deploy.sh -t template.yaml -b s3-bucket-cf-234 -o template-packaged.yaml -s s3-ses-stack3 -r us-east-1
    ```