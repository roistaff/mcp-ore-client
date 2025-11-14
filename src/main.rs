use reqwest::blocking::Client;
use anyhow::Result;
use rmcp::{
    ServiceExt,
    model::{CallToolRequestParam, ClientCapabilities, ClientInfo, Implementation},
    transport::StreamableHttpClientTransport,
};
use serde_json::json;
#[tokio::main]
async fn main() -> Result<()> {
   let transport = StreamableHttpClientTransport::from_uri("http://localhost:8000/mcp");
    let client_info = ClientInfo {
        protocol_version: Default::default(),
        capabilities: ClientCapabilities::default(),
        client_info: Implementation {
            name: "ore ore client".to_string(),
            title: None,
            version: "0.0.1".to_string(),
            website_url: None,
            icons: None,
        },
    };
    let client = client_info.serve(transport).await.inspect_err(|e| {
        panic!("{}",e);
    })?;
    let server_info = client.peer_info();
    let tools = client.list_tools(Default::default()).await?;
    println!("{:#?}",tools);
    let post = json!({
        
    })
    let tool_result = client
        .call_tool(CallToolRequestParam {
            name: "toolname".into(),
            arguments: serde_json::json!({}).as_object().cloned(),
        })
        .await?;
    client.cancel().await?;
    Ok(())
}

