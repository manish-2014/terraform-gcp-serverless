# 1. Get the function URI
#FUNCTION_URI=$(tofu output -raw batch_submitter_cloud_function_uri)
FUNCTION_URI=$(tofu output -raw http_batch_submitter_function_uri)

# 2. (Optional but recommended) Get an identity token for authentication
#    Ensure you are authenticated with gcloud: gcloud auth login
#    And your current gcloud user has permission to invoke the function (e.g., Cloud Functions Invoker role)
AUTH_TOKEN=$(gcloud auth print-identity-token)

# 3. Prepare your JSON payload in a file (e.g., payload.json) or inline
#    Let's assume payload.json contains the example JSON from step 2.
#    echo '{ "job_name_prefix": "my-java-test-run-", "java_app_args": ["--input-file", "gs://your-input-bucket/data/my_data.txt", "--output-path", "gs://your-output-bucket/results/", "--processing-mode", "FAST"], "container_env_vars": { "JAVA_TOOL_OPTIONS": "-Xmx2g -Xms512m", "CONFIG_PROFILE": "production" }}' > payload.json


# 4. Send the POST request
curl -X POST "${FUNCTION_URI}" \
  -H "Authorization: Bearer ${AUTH_TOKEN}" \
  -H "Content-Type: application/json" \
  -d @payload.json 

# Or with inline data:
# curl -X POST "${FUNCTION_URI}" \
#  -H "Authorization: Bearer ${AUTH_TOKEN}" \
#  -H "Content-Type: application/json" \
#  -d '{ "job_name_prefix": "my-java-test-run-", "java_app_args": ["arg1", "value1"] }'