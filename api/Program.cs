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

var app = builder.Build();

// Configure the HTTP request pipeline
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseCors();
app.UseAuthorization();
app.MapControllers();

app.Run();

// Make Program accessible to tests
public partial class Program { }
