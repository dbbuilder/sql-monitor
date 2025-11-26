import { Nav } from "@/components/nav";
import { Footer } from "@/components/footer";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import Link from "next/link";
import { Book, Github, Terminal, Cloud, Server, Lock } from "lucide-react";
import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Documentation - SQL Monitor",
  description: "Complete documentation for SQL Monitor including quick start, deployment guides for Azure, AWS, and on-premise, and API reference.",
};

export default function DocsPage() {
  return (
    <>
      <Nav />
      <main className="flex-1">
        {/* Hero */}
        <section className="border-b bg-muted/50 py-20">
          <div className="container mx-auto px-4 text-center">
            <Book className="mx-auto mb-4 h-12 w-12 text-primary" />
            <h1 className="mb-4 text-4xl font-bold tracking-tight sm:text-5xl">Documentation</h1>
            <p className="mx-auto max-w-2xl text-lg text-muted-foreground">
              Everything you need to deploy and configure SQL Monitor
            </p>
          </div>
        </section>

        {/* Quick Start */}
        <section id="quickstart" className="py-20">
          <div className="container mx-auto px-4">
            <h2 className="mb-8 text-3xl font-bold">Quick Start</h2>
            <div className="mx-auto max-w-3xl space-y-8">
              <Card>
                <CardHeader>
                  <CardTitle className="flex items-center gap-2">
                    <Terminal className="h-5 w-5 text-primary" />
                    Step 1: Clone Repository
                  </CardTitle>
                </CardHeader>
                <CardContent>
                  <pre className="overflow-x-auto rounded-lg bg-muted p-4">
                    <code>
                      {`git clone https://github.com/dbbuilder/sql-monitor.git
cd sql-monitor`}
                    </code>
                  </pre>
                </CardContent>
              </Card>

              <Card>
                <CardHeader>
                  <CardTitle className="flex items-center gap-2">
                    <Server className="h-5 w-5 text-primary" />
                    Step 2: Setup Database
                  </CardTitle>
                  <CardDescription>
                    Choose your central SQL Server and execute the database setup scripts
                  </CardDescription>
                </CardHeader>
                <CardContent>
                  <pre className="overflow-x-auto rounded-lg bg-muted p-4">
                    <code>
                      {`# Connect to SQL Server
sqlcmd -S your-server,1433 -U sa -P YourPassword

# Execute scripts in numerical order
:r database/01-create-database.sql
:r database/02-create-tables.sql
:r database/03-create-partitions.sql
:r database/04-create-procedures.sql
# ... continue through all scripts`}
                    </code>
                  </pre>
                  <p className="mt-4 text-sm text-muted-foreground">
                    Or use the deployment script: <code>./deploy-all.sql</code>
                  </p>
                </CardContent>
              </Card>

              <Card>
                <CardHeader>
                  <CardTitle className="flex items-center gap-2">
                    <Cloud className="h-5 w-5 text-primary" />
                    Step 3: Deploy Grafana Container
                  </CardTitle>
                  <CardDescription>
                    Choose your deployment method: Azure, AWS, or On-Premise
                  </CardDescription>
                </CardHeader>
                <CardContent>
                  <div className="space-y-4">
                    <div>
                      <h4 className="mb-2 font-semibold">Docker Compose (On-Premise)</h4>
                      <pre className="overflow-x-auto rounded-lg bg-muted p-4">
                        <code>
                          {`# Create .env file
cat > .env <<EOF
DB_CONNECTION_STRING=Server=your-server,1433;Database=MonitoringDB;...
GRAFANA_PASSWORD=admin
EOF

# Start container
docker-compose up -d

# Access Grafana at http://localhost:9001`}
                        </code>
                      </pre>
                    </div>

                    <div>
                      <h4 className="mb-2 font-semibold">Azure Container Instances</h4>
                      <pre className="overflow-x-auto rounded-lg bg-muted p-4">
                        <code>
                          {`# Deploy to Azure
./Deploy-Grafana-Update-ACR.ps1

# Access at:
# http://your-container.azurecontainer.io:3000`}
                        </code>
                      </pre>
                    </div>

                    <div>
                      <h4 className="mb-2 font-semibold">AWS ECS Fargate</h4>
                      <pre className="overflow-x-auto rounded-lg bg-muted p-4">
                        <code>
                          {`# Deploy to AWS
./Deploy-AWS.sh

# Access via Application Load Balancer`}
                        </code>
                      </pre>
                    </div>
                  </div>
                </CardContent>
              </Card>

              <Card>
                <CardHeader>
                  <CardTitle>Step 4: Configure Dashboards</CardTitle>
                  <CardDescription>Dashboards are automatically provisioned on startup</CardDescription>
                </CardHeader>
                <CardContent>
                  <p className="text-sm text-muted-foreground">
                    23 dashboards are included and configured automatically. Access the Dashboard
                    Browser to explore all available dashboards:
                  </p>
                  <ul className="mt-4 space-y-2 text-sm">
                    <li className="flex items-start">
                      <span className="mr-2 text-primary">•</span>
                      <span>Instance Health - Overview of all servers</span>
                    </li>
                    <li className="flex items-start">
                      <span className="mr-2 text-primary">•</span>
                      <span>Query Store - Plan regression analysis</span>
                    </li>
                    <li className="flex items-start">
                      <span className="mr-2 text-primary">•</span>
                      <span>Wait Statistics - Performance bottlenecks</span>
                    </li>
                    <li className="flex items-start">
                      <span className="mr-2 text-primary">•</span>
                      <span>Blocking & Deadlocks - Real-time monitoring</span>
                    </li>
                  </ul>
                </CardContent>
              </Card>

              <Card>
                <CardHeader>
                  <CardTitle>Step 5: Start Monitoring</CardTitle>
                  <CardDescription>SQL Agent jobs automatically collect metrics every 5 minutes</CardDescription>
                </CardHeader>
                <CardContent>
                  <p className="mb-4 text-sm text-muted-foreground">
                    That&apos;s it! Your SQL Servers are now being monitored. The SQL Agent jobs will
                    push metrics to the central database automatically.
                  </p>
                  <div className="rounded-lg bg-primary/10 p-4">
                    <p className="text-sm font-medium">
                      ✓ Real-time metrics collection (&lt;1% CPU overhead)
                    </p>
                    <p className="text-sm font-medium">
                      ✓ 90-day retention with automatic cleanup
                    </p>
                    <p className="text-sm font-medium">
                      ✓ Automated alerting via Grafana
                    </p>
                    <p className="text-sm font-medium">✓ PDF export for reports</p>
                  </div>
                </CardContent>
              </Card>
            </div>
          </div>
        </section>

        {/* Deployment Guides */}
        <section id="deployment" className="border-t bg-muted/50 py-20">
          <div className="container mx-auto px-4">
            <h2 className="mb-8 text-3xl font-bold">Deployment Guides</h2>
            <div className="grid gap-6 md:grid-cols-3">
              <Card>
                <CardHeader>
                  <CardTitle>Azure Deployment</CardTitle>
                  <CardDescription>Deploy to Azure Container Instances with optional SSL</CardDescription>
                </CardHeader>
                <CardContent className="space-y-4">
                  <p className="text-sm text-muted-foreground">
                    Step-by-step guide for deploying SQL Monitor to Azure with Application Gateway
                    for SSL termination.
                  </p>
                  <Button asChild variant="outline" className="w-full">
                    <Link
                      href="https://github.com/dbbuilder/sql-monitor/blob/main/docs/SSL-SETUP-AZURE.md"
                      target="_blank"
                    >
                      View Guide
                    </Link>
                  </Button>
                </CardContent>
              </Card>

              <Card>
                <CardHeader>
                  <CardTitle>AWS Deployment</CardTitle>
                  <CardDescription>Deploy to AWS ECS Fargate with ALB and ACM</CardDescription>
                </CardHeader>
                <CardContent className="space-y-4">
                  <p className="text-sm text-muted-foreground">
                    Complete guide for deploying to AWS with Application Load Balancer and free SSL
                    certificates from ACM.
                  </p>
                  <Button asChild variant="outline" className="w-full">
                    <Link
                      href="https://github.com/dbbuilder/sql-monitor/blob/main/docs/SSL-SETUP-AWS.md"
                      target="_blank"
                    >
                      View Guide
                    </Link>
                  </Button>
                </CardContent>
              </Card>

              <Card>
                <CardHeader>
                  <CardTitle>On-Premise Docker</CardTitle>
                  <CardDescription>Deploy to your own infrastructure with Docker</CardDescription>
                </CardHeader>
                <CardContent className="space-y-4">
                  <p className="text-sm text-muted-foreground">
                    Simple Docker Compose deployment for on-premise or self-hosted environments.
                  </p>
                  <Button asChild variant="outline" className="w-full">
                    <Link
                      href="https://github.com/dbbuilder/sql-monitor/blob/main/deployment/DEPLOY-ONPREMISE.md"
                      target="_blank"
                    >
                      View Guide
                    </Link>
                  </Button>
                </CardContent>
              </Card>
            </div>
          </div>
        </section>

        {/* Security */}
        <section id="security" className="border-t py-20">
          <div className="container mx-auto px-4">
            <div className="mx-auto max-w-3xl">
              <div className="mb-8 flex items-center gap-3">
                <Lock className="h-8 w-8 text-primary" />
                <h2 className="text-3xl font-bold">Security & Authentication</h2>
              </div>

              <div className="space-y-6">
                <Card>
                  <CardHeader>
                    <CardTitle>JWT Authentication</CardTitle>
                  </CardHeader>
                  <CardContent>
                    <p className="mb-4 text-sm text-muted-foreground">
                      SQL Monitor API uses JWT tokens with 8-hour expiration. Configure in your
                      appsettings.json:
                    </p>
                    <pre className="overflow-x-auto rounded-lg bg-muted p-4">
                      <code>
                        {`{
  "Jwt": {
    "SecretKey": "your-256-bit-secret",
    "Issuer": "SqlMonitor.Api",
    "Audience": "SqlMonitor.Client",
    "ExpirationHours": 8
  }
}`}
                      </code>
                    </pre>
                  </CardContent>
                </Card>

                <Card>
                  <CardHeader>
                    <CardTitle>Multi-Factor Authentication (MFA)</CardTitle>
                  </CardHeader>
                  <CardContent>
                    <p className="text-sm text-muted-foreground">
                      TOTP-based MFA with QR code generation. Users scan the QR code with Google
                      Authenticator, Authy, or any TOTP-compatible app. 10 backup codes are
                      generated for account recovery.
                    </p>
                  </CardContent>
                </Card>

                <Card>
                  <CardHeader>
                    <CardTitle>Role-Based Access Control (RBAC)</CardTitle>
                  </CardHeader>
                  <CardContent>
                    <p className="text-sm text-muted-foreground">
                      Flexible roles and permissions system allows fine-grained access control.
                      Default roles include Administrator, Developer, and Read-Only.
                    </p>
                  </CardContent>
                </Card>
              </div>
            </div>
          </div>
        </section>

        {/* Additional Resources */}
        <section className="border-t bg-muted/50 py-20">
          <div className="container mx-auto px-4">
            <h2 className="mb-8 text-center text-3xl font-bold">Additional Resources</h2>
            <div className="mx-auto grid max-w-4xl gap-6 md:grid-cols-2">
              <Card>
                <CardHeader>
                  <CardTitle className="flex items-center gap-2">
                    <Github className="h-5 w-5 text-primary" />
                    GitHub Repository
                  </CardTitle>
                </CardHeader>
                <CardContent>
                  <p className="mb-4 text-sm text-muted-foreground">
                    Source code, issues, pull requests, and community discussions
                  </p>
                  <Button asChild variant="outline" className="w-full">
                    <Link href="https://github.com/dbbuilder/sql-monitor" target="_blank">
                      Visit Repository
                    </Link>
                  </Button>
                </CardContent>
              </Card>

              <Card>
                <CardHeader>
                  <CardTitle>API Reference</CardTitle>
                </CardHeader>
                <CardContent>
                  <p className="mb-4 text-sm text-muted-foreground">
                    Interactive Swagger/OpenAPI documentation for the REST API
                  </p>
                  <Button asChild variant="outline" className="w-full">
                    <Link href="https://github.com/dbbuilder/sql-monitor/blob/main/docs/API-INTEGRATION-PLAN.md" target="_blank">
                      View API Docs
                    </Link>
                  </Button>
                </CardContent>
              </Card>

              <Card>
                <CardHeader>
                  <CardTitle>Dashboard Customization</CardTitle>
                </CardHeader>
                <CardContent>
                  <p className="mb-4 text-sm text-muted-foreground">
                    Learn how to create custom Grafana dashboards and panels
                  </p>
                  <Button asChild variant="outline" className="w-full">
                    <Link href="https://grafana.com/docs/" target="_blank">
                      Grafana Docs
                    </Link>
                  </Button>
                </CardContent>
              </Card>

              <Card>
                <CardHeader>
                  <CardTitle>Community Support</CardTitle>
                </CardHeader>
                <CardContent>
                  <p className="mb-4 text-sm text-muted-foreground">
                    Get help from the community or report issues on GitHub
                  </p>
                  <Button asChild variant="outline" className="w-full">
                    <Link href="https://github.com/dbbuilder/sql-monitor/issues" target="_blank">
                      GitHub Issues
                    </Link>
                  </Button>
                </CardContent>
              </Card>
            </div>
          </div>
        </section>

        {/* CTA */}
        <section className="border-t py-20">
          <div className="container mx-auto px-4 text-center">
            <h2 className="mb-4 text-3xl font-bold">Need Help Getting Started?</h2>
            <p className="mx-auto mb-8 max-w-2xl text-lg text-muted-foreground">
              Contact us for migration assistance, custom dashboard development, or training
            </p>
            <Button asChild size="lg">
              <Link href="/contact">Contact Support</Link>
            </Button>
          </div>
        </section>
      </main>
      <Footer />
    </>
  );
}
