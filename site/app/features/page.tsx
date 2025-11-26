import { Nav } from "@/components/nav";
import { Footer } from "@/components/footer";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import Link from "next/link";
import {
  Activity,
  BarChart3,
  AlertTriangle,
  Database,
  Code2,
  Lock,
  Zap,
  TrendingUp,
  Shield,
  FileText,
  Clock,
  HardDrive,
  Cpu,
  Network,
  Search,
  ListChecks,
  GitBranch,
  FileCode,
  Download,
  Globe,
} from "lucide-react";
import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Features - SQL Monitor",
  description: "Comprehensive SQL Server monitoring features including real-time metrics, 23 dashboards, T-SQL code editor, automated alerting, and more.",
};

export default function FeaturesPage() {
  const coreFeatures = [
    {
      icon: Activity,
      title: "Real-Time Performance Monitoring",
      description: "Collect DMV metrics every 5 minutes with <1% CPU overhead",
      details: [
        "CPU, memory, disk I/O metrics",
        "Wait statistics trending",
        "Active session monitoring",
        "Tempdb utilization tracking",
      ],
    },
    {
      icon: BarChart3,
      title: "23 Pre-Built Grafana Dashboards",
      description: "Production-ready dashboards for comprehensive monitoring",
      details: [
        "Instance health overview",
        "Query Store analysis",
        "Wait statistics breakdown",
        "Blocking chain detection",
        "AWS RDS Performance Insights equivalent",
        "Index maintenance recommendations",
      ],
    },
    {
      icon: Code2,
      title: "T-SQL Code Editor",
      description: "Analyze and edit stored procedures with real-time insights",
      details: [
        "30+ code analysis rules",
        "Syntax highlighting",
        "Auto-save functionality",
        "Historical performance data integration",
      ],
    },
    {
      icon: AlertTriangle,
      title: "Automated Alerting System",
      description: "Configure rules for proactive monitoring",
      details: [
        "CPU/memory threshold alerts",
        "Disk space warnings",
        "Deadlock detection",
        "Blocking chain notifications",
        "Query Store regression alerts",
      ],
    },
    {
      icon: TrendingUp,
      title: "Performance Insights",
      description: "AWS RDS Performance Insights for on-premise SQL Server",
      details: [
        "Top SQL by duration, CPU, reads",
        "Wait event analysis",
        "Session activity tracking",
        "Resource contention identification",
      ],
    },
    {
      icon: Database,
      title: "Query Store Integration",
      description: "Track query performance over time",
      details: [
        "Plan regression detection",
        "Forced plan management",
        "Historical execution stats",
        "Parameter sensitivity analysis",
      ],
    },
  ];

  const dashboards = [
    {
      category: "Core Monitoring",
      items: [
        "Dashboard Browser - Central navigation",
        "SQL Server Monitoring - Instance health overview",
        "Performance Analysis - Detailed metrics drilldown",
        "Detailed Metrics - Time-series charts",
      ],
    },
    {
      category: "Database Management",
      items: [
        "Table Browser - Schema exploration",
        "Table Details - Column/index analysis",
        "Code Browser - Stored procedure catalog",
        "Code Viewer - T-SQL editor with analysis",
      ],
    },
    {
      category: "Performance Tuning",
      items: [
        "Query Store - Plan regression tracking",
        "AWS RDS Performance Insights - Top SQL analysis",
        "Server Health Score - Composite health metrics",
        "Query Performance Advisor - Optimization recommendations",
      ],
    },
    {
      category: "Operations",
      items: [
        "DBCC Integrity Checks - Corruption detection",
        "Index Maintenance - Fragmentation analysis",
        "Alert Monitoring - Active alerts dashboard",
        "Audit Logging - Security audit trail",
      ],
    },
    {
      category: "Capacity Planning",
      items: [
        "Baseline Comparison - Historical comparisons",
        "Trend Analysis - Growth projections",
        "Capacity Planning - Resource forecasting",
      ],
    },
  ];

  const technicalFeatures = [
    {
      icon: Zap,
      title: "Push Architecture",
      description: "Each server collects its own metrics and pushes to central database",
      benefit: "Scales to 100+ servers with no central bottleneck",
    },
    {
      icon: HardDrive,
      title: "Columnstore Compression",
      description: "10x compression on performance metrics table",
      benefit: "90-day retention uses minimal disk space",
    },
    {
      icon: Clock,
      title: "Automatic Partitioning",
      description: "Monthly partitions with sliding window maintenance",
      benefit: "Fast queries and automatic old data cleanup",
    },
    {
      icon: Lock,
      title: "Row-Level Security",
      description: "Stored procedures enforce security at database level",
      benefit: "No dynamic SQL in application code",
    },
    {
      icon: Download,
      title: "PDF/PNG Export",
      description: "Built-in Grafana image renderer for dashboard export",
      benefit: "Professional reports with one click",
    },
    {
      icon: Globe,
      title: "Multi-Cloud Ready",
      description: "Deploy to Azure, AWS, GCP, or on-premise",
      benefit: "No vendor lock-in, deploy anywhere",
    },
  ];

  const securityFeatures = [
    {
      title: "JWT Authentication",
      description: "Secure API access with 8-hour token expiration",
    },
    {
      title: "TOTP-Based MFA",
      description: "Time-based one-time passwords with QR code generation",
    },
    {
      title: "BCrypt Password Hashing",
      description: "Industry-standard password security with automatic salting",
    },
    {
      title: "Backup Codes",
      description: "10 single-use codes for MFA recovery",
    },
    {
      title: "Session Management",
      description: "Track active sessions with automatic cleanup",
    },
    {
      title: "Comprehensive Audit Logging",
      description: "All API requests logged with user, action, IP, timestamp",
    },
    {
      title: "Role-Based Access Control (RBAC)",
      description: "Flexible roles and permissions system",
    },
  ];

  return (
    <>
      <Nav />
      <main className="flex-1">
        {/* Hero */}
        <section className="border-b bg-muted/50 py-20">
          <div className="container mx-auto px-4 text-center">
            <h1 className="mb-4 text-4xl font-bold tracking-tight sm:text-5xl">
              Comprehensive SQL Server Monitoring
            </h1>
            <p className="mx-auto max-w-2xl text-lg text-muted-foreground">
              Everything you need to monitor, analyze, and optimize SQL Server performance in one
              self-hosted solution
            </p>
          </div>
        </section>

        {/* Core Features */}
        <section className="py-20">
          <div className="container mx-auto px-4">
            <h2 className="mb-12 text-center text-3xl font-bold">Core Features</h2>
            <div className="grid gap-8 md:grid-cols-2 lg:grid-cols-3">
              {coreFeatures.map((feature) => {
                const Icon = feature.icon;
                return (
                  <Card key={feature.title} className="h-full">
                    <CardHeader>
                      <div className="mb-4 flex h-12 w-12 items-center justify-center rounded-lg bg-primary/10">
                        <Icon className="h-6 w-6 text-primary" />
                      </div>
                      <CardTitle>{feature.title}</CardTitle>
                      <CardDescription>{feature.description}</CardDescription>
                    </CardHeader>
                    <CardContent>
                      <ul className="space-y-2 text-sm text-muted-foreground">
                        {feature.details.map((detail) => (
                          <li key={detail} className="flex items-start">
                            <span className="mr-2 mt-1 text-primary">•</span>
                            <span>{detail}</span>
                          </li>
                        ))}
                      </ul>
                    </CardContent>
                  </Card>
                );
              })}
            </div>
          </div>
        </section>

        {/* Dashboards */}
        <section className="border-t bg-muted/50 py-20">
          <div className="container mx-auto px-4">
            <h2 className="mb-4 text-center text-3xl font-bold">23 Pre-Built Dashboards</h2>
            <p className="mb-12 text-center text-lg text-muted-foreground">
              Production-ready Grafana dashboards covering every aspect of SQL Server monitoring
            </p>

            <div className="grid gap-8 md:grid-cols-2 lg:grid-cols-3">
              {dashboards.map((category) => (
                <Card key={category.category}>
                  <CardHeader>
                    <CardTitle className="text-lg">{category.category}</CardTitle>
                  </CardHeader>
                  <CardContent>
                    <ul className="space-y-2 text-sm">
                      {category.items.map((item) => (
                        <li key={item} className="flex items-start text-muted-foreground">
                          <span className="mr-2 mt-1 text-primary">✓</span>
                          <span>{item}</span>
                        </li>
                      ))}
                    </ul>
                  </CardContent>
                </Card>
              ))}
            </div>
          </div>
        </section>

        {/* Technical Features */}
        <section className="py-20">
          <div className="container mx-auto px-4">
            <h2 className="mb-12 text-center text-3xl font-bold">Technical Excellence</h2>
            <div className="grid gap-6 md:grid-cols-2 lg:grid-cols-3">
              {technicalFeatures.map((feature) => {
                const Icon = feature.icon;
                return (
                  <Card key={feature.title}>
                    <CardHeader>
                      <div className="mb-2 flex items-center gap-3">
                        <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-primary/10">
                          <Icon className="h-5 w-5 text-primary" />
                        </div>
                        <CardTitle className="text-lg">{feature.title}</CardTitle>
                      </div>
                      <CardDescription>{feature.description}</CardDescription>
                    </CardHeader>
                    <CardContent>
                      <div className="rounded-lg bg-muted/50 p-3 text-sm">
                        <span className="font-medium text-foreground">Benefit:</span>{" "}
                        <span className="text-muted-foreground">{feature.benefit}</span>
                      </div>
                    </CardContent>
                  </Card>
                );
              })}
            </div>
          </div>
        </section>

        {/* Security Features */}
        <section className="border-t bg-muted/50 py-20">
          <div className="container mx-auto px-4">
            <div className="mb-12 text-center">
              <Shield className="mx-auto mb-4 h-12 w-12 text-primary" />
              <h2 className="mb-4 text-3xl font-bold">Enterprise Security</h2>
              <p className="mx-auto max-w-2xl text-lg text-muted-foreground">
                SOC 2 compliance-ready with authentication, authorization, and comprehensive audit logging
              </p>
            </div>

            <div className="mx-auto max-w-3xl">
              <Card>
                <CardContent className="pt-6">
                  <div className="grid gap-6 md:grid-cols-2">
                    {securityFeatures.map((feature) => (
                      <div key={feature.title} className="flex items-start gap-3">
                        <Lock className="mt-1 h-5 w-5 flex-shrink-0 text-primary" />
                        <div>
                          <div className="font-medium">{feature.title}</div>
                          <div className="text-sm text-muted-foreground">{feature.description}</div>
                        </div>
                      </div>
                    ))}
                  </div>
                </CardContent>
              </Card>
            </div>
          </div>
        </section>

        {/* CTA */}
        <section className="border-t py-20">
          <div className="container mx-auto px-4 text-center">
            <h2 className="mb-4 text-3xl font-bold">Ready to Get Started?</h2>
            <p className="mx-auto mb-8 max-w-2xl text-lg text-muted-foreground">
              Deploy SQL Monitor in 5 minutes and start monitoring your SQL Servers today
            </p>
            <div className="flex flex-col gap-4 sm:flex-row sm:justify-center">
              <Button asChild size="lg">
                <Link href="/docs">Read Documentation</Link>
              </Button>
              <Button asChild variant="outline" size="lg">
                <Link href="/pricing">See Pricing</Link>
              </Button>
            </div>
          </div>
        </section>
      </main>
      <Footer />
    </>
  );
}
