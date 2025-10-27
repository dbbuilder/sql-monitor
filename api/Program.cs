using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.IdentityModel.Tokens;
using System.Text;
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
builder.Services.AddScoped<IPasswordService, PasswordService>();
builder.Services.AddScoped<IJwtService, JwtService>();
builder.Services.AddMemoryCache(); // For permission caching

// Configure connection string
var connectionString = builder.Configuration.GetConnectionString("MonitoringDB")
    ?? throw new InvalidOperationException("Connection string 'MonitoringDB' not found.");

builder.Services.AddSingleton(new SqlConnectionFactory(connectionString));

// Configure JWT Authentication
var jwtSecretKey = builder.Configuration["Jwt:SecretKey"]
    ?? throw new InvalidOperationException("JWT SecretKey not configured");
var jwtIssuer = builder.Configuration["Jwt:Issuer"] ?? "SqlMonitor.Api";
var jwtAudience = builder.Configuration["Jwt:Audience"] ?? "SqlMonitor.Client";

builder.Services.AddAuthentication(options =>
{
    options.DefaultAuthenticateScheme = JwtBearerDefaults.AuthenticationScheme;
    options.DefaultChallengeScheme = JwtBearerDefaults.AuthenticationScheme;
})
.AddJwtBearer(options =>
{
    options.TokenValidationParameters = new TokenValidationParameters
    {
        ValidateIssuerSigningKey = true,
        IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwtSecretKey)),
        ValidateIssuer = true,
        ValidIssuer = jwtIssuer,
        ValidateAudience = true,
        ValidAudience = jwtAudience,
        ValidateLifetime = true,
        ClockSkew = TimeSpan.FromMinutes(5)
    };
});

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

// Add authentication middleware (JWT validation)
app.UseAuthentication();

// Register authorization middleware (AFTER authentication, BEFORE controllers)
// This enforces permission-based access control
app.UseMiddleware<AuthorizationMiddleware>();

app.UseCors();
app.UseAuthorization();
app.MapControllers();

app.Run();

// Make Program accessible to tests
public partial class Program { }
