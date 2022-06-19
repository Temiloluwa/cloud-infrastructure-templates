#!/bin/sh
while getopts t:b:o:s:r: flag
do
    case "${flag}" in
        t) template=${OPTARG};;
        b) bucket=${OPTARG};;
        o) output=${OPTARG};;
        s) stackname=${OPTARG};;
        r) region=${OPTARG};;
    esac
done

echo "region: $region";
echo "cloudformation template: $template";
echo "cloudformation template s3 bucket name: $bucket";
echo "cloudformation output template: $output";
echo "cloudformation stack name: $stackname";

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
