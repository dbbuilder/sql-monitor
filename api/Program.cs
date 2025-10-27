using SqlMonitor.Api.Middleware;
using SqlMonitor.Api.Services;

var builder = WebApplication.CreateBuilder(args);

// Add services to the container
builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(c =>
{
    c.SwaggerDoc("v1", new() {
        Title = "SQL Server Monitor API",
        Version = "v1",
        Description = "Self-hosted SQL Server monitoring API using Dapper and stored procedures"
    });
});

// Register services
builder.Services.AddScoped<ISqlService, SqlService>();

// Configure connection string
var connectionString = builder.Configuration.GetConnectionString("MonitoringDB")
    ?? throw new InvalidOperationException("Connection string 'MonitoringDB' not found.");

builder.Services.AddSingleton(new SqlConnectionFactory(connectionString));

// Add CORS
builder.Services.AddCors(options =>
{
    options.AddDefaultPolicy(policy =>
    {
        policy.AllowAnyOrigin()
              .AllowAnyMethod()
              .AllowAnyHeader();
    });
});

// Configure Kestrel to use port 9000
builder.WebHost.ConfigureKestrel(serverOptions =>
{
    serverOptions.ListenLocalhost(9000);
});

var app = builder.Build();

// Configure the HTTP request pipeline
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

// Register audit middleware (BEFORE authentication/authorization)
// This ensures all requests are logged, even unauthorized ones
app.UseMiddleware<AuditMiddleware>();

app.UseCors();
app.UseAuthorization();
app.MapControllers();

app.Run();

// Make Program accessible to tests
public partial class Program { }
