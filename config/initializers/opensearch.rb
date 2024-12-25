require 'opensearch-aws-sigv4'
require 'aws-sigv4'
require 'aws-sdk-core'

OPENSEARCH_AWS_REGION = ENV.fetch("OPENSEARCH_AWS_REGION", "ap-northeast-1")

OPENSEARCH_DEFAULT_ENDPOINT = "https://vpc-research-rag-sb6x3qpic4xkjo72av4efshyja.ap-northeast-1.es.amazonaws.com"
OPENSEARCH_ENDPOINT = ENV.fetch("OPENSEARCH_ENDPOINT", OPENSEARCH_DEFAULT_ENDPOINT)
