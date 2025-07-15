using System.Diagnostics;
using Microsoft.Extensions.Logging;

namespace RedisService
{
    class Program
    {
        static void Main(string[] args)
        {
            string configFilePath = "redis.conf";

            // Parse command line arguments
            for (int i = 0; i < args.Length; i++)
            {
                if (args[i] == "-c" && i + 1 < args.Length)
                {
                    configFilePath = args[i + 1];
                    break;
                }
            }

            try
            {
                IHost host = Host.CreateDefaultBuilder(args)
                    .UseWindowsService(options =>
                    {
                        options.ServiceName = "Redis Server";
                    })
                    .ConfigureLogging(logging =>
                    {
                        if (OperatingSystem.IsWindows())
                        {
                            logging.AddEventLog();
                        }
                        logging.SetMinimumLevel(LogLevel.Information);
                    })
                    .ConfigureServices((hostContext, services) =>
                    {
                        services.AddHostedService(serviceProvider =>
                            new RedisService(configFilePath, serviceProvider.GetRequiredService<ILogger<RedisService>>()));
                    })
                    .Build();

                host.Run();
            }
            catch (Exception ex)
            {
                // Log to Windows Event Log if possible
                try
                {
                    if (OperatingSystem.IsWindows())
                    {
                        EventLog.WriteEntry("Redis Service", $"Failed to start Redis service: {ex.Message}", EventLogEntryType.Error);
                    }
                }
                catch
                {
                    // If event log fails, write to console
                    Console.WriteLine($"Failed to start Redis service: {ex.Message}");
                }
                
                Environment.Exit(1);
            }
        }
    }



    public class RedisService : BackgroundService
    {
        private readonly string configFilePath;
        private readonly ILogger<RedisService> logger;
        private Process? redisProcess;

        public RedisService(string configFilePath, ILogger<RedisService> logger)
        {
            this.configFilePath = configFilePath;
            this.logger = logger;
        }

        public override Task StartAsync(CancellationToken stoppingToken)
        {
            try
            {
                var basePath = Path.Combine(AppContext.BaseDirectory);
                string resolvedConfigPath = configFilePath;

                if (!Path.IsPathRooted(configFilePath))
                {
                    resolvedConfigPath = Path.Combine(basePath, configFilePath);
                }

                resolvedConfigPath = Path.GetFullPath(resolvedConfigPath);

                logger.LogInformation("Starting Redis server with config: {ConfigPath}", resolvedConfigPath);

                // Verify config file exists
                if (!File.Exists(resolvedConfigPath))
                {
                    logger.LogWarning("Config file not found: {ConfigPath}, Redis will use defaults", resolvedConfigPath);
                }

                // Check if Redis server executable exists
                string redisServerPath = Path.Combine(basePath, "redis-server.exe");
                if (!File.Exists(redisServerPath))
                {
                    logger.LogError("Redis server executable not found: {RedisServerPath}", redisServerPath);
                    throw new FileNotFoundException($"Redis server executable not found: {redisServerPath}");
                }

                // For MSYS2/Cygwin compatibility, convert Windows path to Unix-style path
                var diskSymbol = resolvedConfigPath[..resolvedConfigPath.IndexOf(":")];
                var fileConf = resolvedConfigPath.Replace(diskSymbol + ":", "/cygdrive/" + diskSymbol).Replace("\\", "/");

                string fileName = redisServerPath.Replace("\\", "/");
                string arguments = $"\"{fileConf}\"";

                logger.LogInformation("Executing: {FileName} {Arguments}", fileName, arguments);

                ProcessStartInfo processStartInfo = new(fileName, arguments)
                {
                    WorkingDirectory = basePath,
                    UseShellExecute = false,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    CreateNoWindow = true
                };

                redisProcess = new Process();
                redisProcess.StartInfo = processStartInfo;
                
                // Log Redis output
                redisProcess.OutputDataReceived += (sender, e) => {
                    if (!string.IsNullOrEmpty(e.Data))
                    {
                        logger.LogInformation("Redis: {Output}", e.Data);
                    }
                };
                
                redisProcess.ErrorDataReceived += (sender, e) => {
                    if (!string.IsNullOrEmpty(e.Data))
                    {
                        logger.LogError("Redis Error: {Error}", e.Data);
                    }
                };

                bool started = redisProcess.Start();
                if (!started)
                {
                    throw new InvalidOperationException("Failed to start Redis process");
                }

                redisProcess.BeginOutputReadLine();
                redisProcess.BeginErrorReadLine();

                logger.LogInformation("Redis server started successfully with PID: {ProcessId}", redisProcess.Id);
                
                return Task.CompletedTask;
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "Failed to start Redis server");
                throw;
            }
        }

        protected override async Task ExecuteAsync(CancellationToken stoppingToken)
        {
            // Monitor the Redis process
            try
            {
                while (!stoppingToken.IsCancellationRequested && redisProcess != null && !redisProcess.HasExited)
                {
                    await Task.Delay(1000, stoppingToken);
                }

                if (redisProcess?.HasExited == true)
                {
                    logger.LogError("Redis process exited unexpectedly with code: {ExitCode}", redisProcess.ExitCode);
                }
            }
            catch (OperationCanceledException)
            {
                // Expected when cancellation is requested
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "Error monitoring Redis process");
            }
        }

        public override Task StopAsync(CancellationToken stoppingToken)
        {
            try
            {
                if (redisProcess != null && !redisProcess.HasExited)
                {
                    logger.LogInformation("Stopping Redis server...");
                    
                    // Try graceful shutdown first
                    try
                    {
                        redisProcess.Kill();
                        redisProcess.WaitForExit(5000); // Wait up to 5 seconds
                    }
                    catch (Exception ex)
                    {
                        logger.LogWarning(ex, "Error during graceful shutdown, forcing termination");
                        redisProcess.Kill();
                    }
                    
                    redisProcess.Dispose();
                    redisProcess = null;
                    
                    logger.LogInformation("Redis server stopped");
                }
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "Error stopping Redis server");
            }

            return Task.CompletedTask;
        }
    }

}
