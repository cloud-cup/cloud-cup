
<div align="center">
  <img src="https://github.com/user-attachments/assets/6b5aae46-2ac0-4c2f-a98c-675f2bf02350"  alt="Cloud Cup">
     <h3>Cloud Cup</h3>
  <p><strong>A High-Performance Reverse Proxy Built in Zig </strong></p>
</div>


**Cloud Cup** is a modern, high-performance reverse proxy built for Linux in Zig, designed to handle today's web traffic demands with speed, scalability, and resilience.

At its core, Cloud Cup implements a master-worker architecture that ensures uninterrupted service, dynamic traffic management, and robust request handling. Whether you’re a developer building microservices or an operations engineer managing web infrastructure, Cloud Cup offers the tools to keep your applications running smoothly and efficiently.

This is **v0.1.0-alpha**, the foundation for an innovative platform that aims to redefine reverse proxy and load balancing solutions.

This proxy is built for developers, DevOps engineers, and cloud infrastructure architects who need high performance, automatic scaling, and dynamic service management.

# Master-Worker Architecture  

Cloud Cup’s architecture revolves around its **master** and **worker processes**, each with distinct responsibilities:  

## Master Process  

- **Validates and applies configurations** at startup, ensuring they are correct before spawning workers.  
- **Hot reloads configurations** via the CLI (`cupctl`), where the CLI process validates the new configuration and distributes it to workers dynamically.  
- Spawns **multiple worker processes** and monitors them to ensure high availability. If a worker process exits unexpectedly, the master immediately spawns a replacement.  
- Manages the CLI command listener, enabling seamless interaction for updates and diagnostics.  

## Worker Process  

- All workers **listen on the same port and address**, leveraging the kernel to distribute incoming requests efficiently among them.  
- Each worker operates with its own **epoll instance** for high-performance request handling.  
- Utilizes an independent **thread pool** to handle requests concurrently, ensuring scalability and responsiveness.  
- Dynamically receives and applies configuration updates from the master process, maintaining consistency across all workers.  

This architecture ensures **Cloud Cup remains operational** even under heavy load or in the event of individual worker failures, delivering unparalleled reliability and performance.  

# 🚀 Key Features
1. HTTP/1 and TLS/SSL Support
   - Reliable and secure connections with BoringSSL.
   - Efficient handling of modern web traffic requirements.

3. Dynamic Load Balancing
   - Implements a Round-Robin Load Balancing strategy.
   - Smooth traffic distribution across backend servers for optimized performance.

5. Seamless Configuration Management
   - Use a simple JSON configuration file to define routes and backends.
   - Hot reloading with [cupctl](https://github.com/cloud-cup/cup-cli) lets you apply new configurations instantly without restarting or interrupting traffic.

7. Optimized for Linux
    - Built for performance using epoll for efficient I/O handling.
    - Written in Zig, taking advantage of its low-level control and modern safety features.

8. Customizable Routes
   Match specific paths or patterns to dedicated backends with granular control.

# 🎯 Why Cloud-Cup?
In the age of cloud computing, having a reliable, scalable, and fast Reverse Proxy is crucial for maintaining the performance and availability of your applications. Cloud-Cup is designed to be:

- Performance: Built with Zig, a low-level language designed for speed and safety.
- lexibility: Dynamically configure routes and backends.
- Ease of Use: Apply changes on the fly with cupctl without downtime.
- Security: Protect your services with modern TLS/SSL.

# Getting Started with Cloud Cup  
## ⚙️ Prerequisites  

Make sure you have the following installed on your system:  

- **Zig 0.13**: The build system requires Zig 0.13 or later.  

To verify your Zig version:  
```bash
zig version
```
## 📦 Downloading Cloud Cup  

You can start by obtaining Cloud Cup in one of two ways:  

1. **Download the release archive**:  
   - Grab the file `cloud-cup-0.1.0-alpha.1.tar.gz` attached to the [v0.1.0-alpha.1 release](https://github.com/cloud-cup/cloud-cup/releases/tag/v0.1.0-alpha.1).  

2. **Clone the project from GitHub**:  
   - To test the `v0.1.0-alpha.1` release, clone the release branch:  
     ```bash
     git clone --branch release-0.1 https://github.com/cloud-cup/cloud-cup.git
     ```  
   - For the latest development version, clone the main branch:  
     ```bash
     git clone https://github.com/cloud-cup/cloud-cup.git
     ```
   - Build the project in release mode:
    ```bash
    zig build -Drelease=true
    ```
After the build completes, you’ll have an executable binary for Cloud Cup. in `zig-out/bin/cloud-cup`

## 🏃 Running Cloud Cup

To run Cloud Cup:

  - Set up your configuration file:
    Create a JSON configuration file (e.g., my_config.json) to define the server settings, routes, and backends. 
    Refer to the [Configuration Guide](https://cloud-cup.netlify.app/docs/3_configuration) for details on how to structure your configuration.

  - Start the application:
    Use the following command to launch Cloud Cup with your configuration file:
    ```bash 
    ./cloud-cup my_config.json
    ```
  - Check if the server is running:
    Once started, Cloud Cup will begin listening for incoming connections based on your configuration.


## 🌟 Roadmap
Here’s what’s coming next for Cloud Cup:
- HTTP/2 Support: Enhance speed and efficiency.
- Load Balancing Strategies: Add weighted round-robin, least connections, and more.
- Metrics and Monitoring: Export stats for integration with Prometheus or Grafana.
- Web Admin Dashboard: Manage configurations through a user-friendly interface.
- Enhanced Protocol Support: QUIC, gRPC, and WebSockets.

## Contributing

Contributions, bug reports, and feature requests are welcome! Please submit them via GitHub Issues. efer to the [Configuration Guide](https://cloud-cup.netlify.app/docs/5_contribute)

