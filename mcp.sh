#initialize
headers=$(curl -s -D - \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  --data '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{"tools":{}},"clientInfo":{"name":"manual-client","version":"1.0.0"}}}' \
  http://127.0.0.1:8000/mcp -o /dev/null)

session_id=$(echo "$headers" | grep -i "mcp-session-id"  | awk -F": " '{print $2}' | tr -d '\r\n')

echo "$session_id"
curl -s -X POST  -H "Content-Type: application/json" -H "mcp-session-id: $session_id" -H "Accept: application/json" --data '{"jsonrpc": "2.0", "method": "notifications/initialized"}' http://127.0.0.1:8000/mcp/ && echo "Initialized!"
# list tools
list=$(curl -s -X POST  -H "Content-Type: application/json"  -H "Accept: application/json" -H "mcp-session-id: $session_id" --data '{ "jsonrpc": "2.0", "id": 1, "method": "tools/list", "params": {}}'  http://127.0.0.1:8000/mcp/)
tool_calling=$(echo "$list" | jq '{tools: [ .result.tools[] | { type: "function", function: { name: .name, description: .description, parameters: { type: "object", properties: (.inputSchema.properties), required: (.inputSchema.required)}}}]}')
user_input=$(gum input)
echo $user_input
output=$(curl -s http://localhost:8080/v1/chat/completions -H "Content-Type: application/json" -d "$(jq -n --argjson tools "$tool_calling" --arg content "$user_input" '{model: "gpt-3.5-turbo", tools: $tools.tools, messages:[{role: "user", content: $content}]}')")
reasoning=$(echo "$output" | jq -r '.choices[0].message.reasoning_content')
echo "Reasoning Content:"
echo "$reasoning"
content=$(echo "$output" | jq -r '.choices[0].message.content // "" ')
echo "Content:"
echo "$content"
tool_calls=$(echo "$output" | jq -r '.choices[0].message.tool_calls // empty')
if [ $? -eq 0 ] && [ -n "$tool_calls" ]; then
    echo "Tool Calls:"
    tool_calls_json=$(echo "$output" | jq -c '.choices[0].message.tool_calls // []')
    tool_name=$(echo "$tool_calls_json" | jq -r '.[0].function.name // empty')
    tool_args=$(echo "$tool_calls_json" | jq -c '.[0].function.arguments // empty')
    tool_args=$(echo $tool_args | sed 's/\\"/"/g' | sed 's/^"\(.*\)"$/\1/' )
    echo $tool_args
    echo "    Tool Name: $tool_name"
    echo "    Tool Arguments: $tool_args"
else
    echo "Tool Calls:"
fi
tool_calling=$(jq -n \
  --arg name "$tool_name" \
  --argjson arguments "$tool_args" \
  '{
    jsonrpc: "2.0",
    id: 1,
    method: "tools/call",
    params: {
      name: $name,
      arguments: $arguments
    }
  }' | jq .)
#echo $tool_calling
output=$(curl -s -X POST -H "Content-Type: application/json"  -H "Accept: application/json" -H "mcp-session-id: $session_id" --data "$tool_calling" http://127.0.0.1:8000/mcp/)
tool_output=$(echo $output | jq -c -r '.result.content[0].text')
echo "Tool Output: $tool_output"

final_post=$(jq -n \
  --arg model "gpt-3.5-turbo" \
  --arg system_content "You are a helpful assistant. Use ONLY the following information to answer questions. Do not use any markdown formatting, code blocks, headers, bold, italics, lists, or special formatting. Provide clear, plain text responses only. Generate responses exclusively based on the outputs from tool_output: $tool_output" \
  --arg user_input "$user_input" \
  '{
    model: $model,
    messages: [
      {role: "system", content: $system_content},
      {role: "user", content: $user_input}
    ]
  }')

#echo $final_post
output=$(curl -s http://localhost:8080/v1/chat/completions -H "Content-Type: application/json" -d "$final_post")
echo $output | jq -r '.choices[0].message.content'
#echo $output | jq -r '.choices[0].message.reasoning_content'
