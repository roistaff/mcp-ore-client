use std::io::Write;
use reqwest::Client;
use serde_json::{Value,json};
use std::error::Error;
use anyhow::Result;
use rmcp::{
    ServiceExt,
    model::{CallToolRequestParam, ClientCapabilities, ClientInfo, Implementation},
    transport::StreamableHttpClientTransport,
};

pub async fn post_llm(url: &str, payload: &Value) -> Result<String> {
    let client = Client::new();
    let response = client
        .post(url)
        .json(payload)
        .send()
        .await?;
    let status = response.status();
    let body = response.text().await?;

    if !status.is_success() {
        panic!("{}",status)
    } else {
        Ok(body)
    }
}

#[tokio::main]
async fn main() -> Result<()> {
    let transport = StreamableHttpClientTransport::from_uri("http://localhost:8000/mcp");
    let client_info = ClientInfo {
        protocol_version: Default::default(),
        capabilities: ClientCapabilities::default(),
        client_info: Implementation {
            name: "i am client".to_string(),
            title: None,
            version: "0.0.1".to_string(),
            website_url: None,
            icons: None,
        },
    };
    let client = client_info.serve(transport).await.inspect_err(|e| {
        eprintln!("client error: {:?}", e);
    })?;

    // Initialize
    let server_info = client.peer_info();
    // println!("Connected to server: {server_info:#?}");
    let user_prompt = user_input("User:");

    // List tools
    let tools = client.list_tools(Default::default()).await?;
    println!("Available tools: {tools:#?}");
    //
    let tool_selection_prompt = "You are an AI agent capable of calling external tools.Available tools:";
let prompt_rules = "Rules:
Analyze the user request and determine which tool (if any) should be used.
If a tool is needed, output only a valid JSON object in the following format:
{\"tool_name\": \"name_of_the_tool_to_use\"}
If no tool is required, output:
{\"tool_name\": \"none\"}
Do not include any explanation, commentary, or additional text.
The output must be valid JSON and nothing else.";
    let mut available_tools = String::new();
    for tool in &tools.tools {
        let name = &tool.name;
        let description = tool.description.as_deref().unwrap_or("(empty string)");
        available_tools.push_str(&format!("\n{} - {}", name, description)); 
    }
    let full_prompt = format!("{}{}\n{}", tool_selection_prompt, available_tools,prompt_rules);
    println!("{}",full_prompt);
    let data = serde_json::json!({
    "messages": [
    {
        "role": "system",
        "content": full_prompt
    },{
        "role":"user",
        "content":user_prompt
    }]}); 
    let url = "http://127.0.0.1:8080/v1/chat/completions";
    let body = post_llm(url, &data).await?;
    let outer: Value = serde_json::from_str(&body)?;
    let content = outer["choices"][0]["message"]["content"]
        .as_str()
        .expect("Missing content field");
    let inner: Value = serde_json::from_str(content)?;
    let tool_name = inner["tool_name"].as_str().unwrap_or("(missing)");
    println!("{}",tool_name);
    for tool in &tools.tools {
        let name = &tool.name;
        if name == tool_name{
            println!("{}",serde_json::to_string(&tool.input_schema).unwrap());
           let description = tool.description.as_deref().unwrap_or("(empty string)");
            let input_schema = serde_json::to_string(&tool.input_schema).unwrap();
            
            println!("Input schema: {}", input_schema);
            
            // Create system prompt for argument generation
            let arg_gen_prompt = format!(
                "Generate a JSON object based on the input schema to call the tool.\n\
                Tool: {}\n\
                Description: {}\n\
                Input schema: {}\n\n\
                Rules:\n\
                - Output must be only valid JSON that matches the schema\n\
                - Do not include any explanation, commentary, or additional text\n\
                - Do not include markdown, code blocks, or extra commentary.
                - The JSON must be a valid object that can be used as tool arguments",
                name, description, input_schema
            );
            
            let arg_data = serde_json::json!({
                "messages": [
                    {
                        "role": "system",
                        "content": arg_gen_prompt
                    },
                    {
                        "role": "user",
                        "content": user_prompt
                    }
                ]
            });
            
            // Call LLM to generate arguments
            let arg_body = post_llm(url, &arg_data).await?;
            let arg_outer: Value = serde_json::from_str(&arg_body)?;
            let arg_content = arg_outer["choices"][0]["message"]["content"]
                .as_str()
                .expect("Missing content field");
            
            println!("Generated arguments: {}", arg_content);
            
            // Parse the generated arguments
            let arguments: Value = serde_json::from_str(arg_content)?;
            
            // Call the tool with generated arguments
            let tool_result = client
                .call_tool(CallToolRequestParam {
                    name: name.clone(),
                    arguments: arguments.as_object().cloned(),
                })
                .await?;
            
            println!("Tool result: {tool_result:#?}");
            break; 
        };
    }
    // let tool_result = client
    //     .call_tool(CallToolRequestParam {
    //         name: "add".into(),
    //         arguments: serde_json::json!({}).as_object().cloned(),
    //     })
    //     .await?;
    // println!("Tool result: {tool_result:#?}");

    client.cancel().await?;
    Ok(())
}

fn user_input(massage: &str) -> String {
    print!("{}", massage);
    std::io::stdout().flush().expect("Failed to flush stdout");
    let mut input = String::new();
    std::io::stdin()
        .read_line(&mut input)
        .expect("Failed to read line");
    input.trim_end().to_owned()
}
