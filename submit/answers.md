## Questions

1. Technical Challenges: Describe the greatest challenge(s) you encountered in translating the template from CloudFormation to Terraform. (1-2 paragraphs)

    The greatest challenge I experienced while translating the template from CloudFormation to Terraform was handling the dpeendencies and references in between resources. In CloudFormation, the dependencies were easier to outline because you could explicitly use "DependOn" property to ensure that one resource can be created before another. In Terraform, the dependencies are more implicit that are built from variable references. This trickled down to different parts of the resources such as the SNS topic policy and the S3 notification system. For example, I needed to ensure that the SNS topic and policy were created before the S3 could reference them. I tried to create the SNS topic after and I ran into deployment issues. 

    Another difference that was challenging was the intrinsic functions like !Ref from CloudFormation to Terraform equivalnets. Terraform has an entirely different structure including syntax like {}[] while CloudFormation was more like bulleted plain English. Ensuring that the spacing and syntax was correct for Terraform was difficult and frustrating as well. 


2. Access Permissions: What element (specify file and line #) grants the SNS subscription permission to send messages to your API? Locate and explain your answer.

The file is main.tf and the line numbers are from 31-47. (resource "aws_sns_topic_policy" "sns_policy") This policy grants the S3 service principle permission to publish messages to the SNS toipc. Once that topic receives the message, the SNS subscription forwards them via HTTP to the endpoint. If this topic policy did not exist, then S3 would not eb able to trigger the SNS topic and the pipeline would not be able to be deployed. 


3. Event flow and reliability: Trace the path of a single CSV file from the moment it is uploaded to raw/ in S3 until the FastAPI app processes it. What happens if the EC2 instance is down or the /notify endpoint returns an error? How does SNS behave (e.g., retries, dead-letter behavior), and what would you change if this needed to be production-grade?

Here is the path: 
- CSV file uploaded to raw/ in S3 
- bucket notification configuration detects the event, sends message to SNS topic 
- SNS topic forward notification to endpoint (FastAPI service on EC2 instance) 
- FastAPI application receives notification payload, extracts S3 info, retrieves CSV file, processes with anomaly detection logic
- Application updates statistical baseline and store updated results back in S3

If the EC2 instance is down or there is an error in the /notify endpoint, then SNS retries delivery. For HTTP subscriptions, SNS retries multiple times over several hours before dropping the message. if all retries fail, and no dead-letter queue is configured then the message may get lost. If we needed this to be at production-grade, you could introduce an SQS queue between SNS and the application. SNS could publish to SWS and EC2 instances could get to queue. 



4. IAM and least privilege: The IAM policy for the EC2 instance grants full access to one S3 bucket. List the specific S3 operations the application actually performs (e.g., GetObject, PutObject, ListBucket). Could you replace the “full access” policy with a minimal set of permissions that still allows the app to work? What would that policy look like?

The specific functions the application uses GetObject, PutObject, and ListObject. However, the IAM role has a policy that grants full access to the bucket. A more secure/minimal set of permissions could look like: 
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject"
      ],
      "Resource": "arn:aws:s3:::BUCKET_NAME/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket"
      ],
      "Resource": "arn:aws:s3:::BUCKET_NAME"
    }
  ]
}

This allows the application to read and write to the bucket and list contents while preventing other unecessary operations like deleting buckets or modifying bucket policies. 


5. Architecture and scaling: This solution uses batch-file events (S3 + SNS) to drive processing, with a rolling statistical baseline in memory and in S3. How would the design change if you needed to handle 100x more CSV files per hour, or if multiple EC2 instances were processing files from the same bucket? Address consistency of the shared baseline.json, concurrent processing, and any tradeoffs.

This current architecture would work well for smaller workloads but would definitely face limitations if the system needed to process a higher amount of CSV files and support multiple EC2 instances. A single EC2 instance handling HTTP notifications directly from SNS could create a bottleneck. Something to help this would to be create an intermediate message queue such as Amazon SQS. SNS could publish events to the queue and multiple worker instances could pull tasks from the queue and process them all at the same time. This could improve the system and make it more resilient to failures. 

Another challenge is maintaning consistency for the baseline.json file. If multiple EC2 instances attempted to read and update the file at the same time, race conditions could occur, leading to inconsistent baselines. A production-grade system could improve this by storing the baseline in a managed store such as DynamoDB. The tradeoff between these solutions is balancing simplicity, performance, and operational complexity. 




