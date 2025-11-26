import Link from "next/link";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Nav } from "@/components/nav";
import { Footer } from "@/components/footer";
import {
  Activity,
  Database,
  Shield,
  Zap,
  BarChart3,
  AlertTriangle,
  Code2,
  Cloud,
  CheckCircle2,
  TrendingUp,
  Clock,
  DollarSign,
} from "lucide-react";

export default function Home() {
  const features = [
    {
      icon: Activity,
      title: "Real-Time Monitoring",
      description: "Track DMV metrics every 5 minutes with <1% CPU overhead using SQL Agent jobs",
    },
    {
      icon: BarChart3,
      title: "23 Pre-Built Dashboards",
      description: "Grafana dashboards for instance health, query store, waits, blocking, and more",
    },
    {
      icon: Code2,
      title: "T-SQL Code Editor",
      description: "Analyze stored procedures with 30+ rules, syntax highlighting, and auto-save",
    },
    {
      icon: AlertTriangle,
      title: "Automated Alerting",
      description: "Configure alert rules for CPU, memory, disk, deadlocks, and blocking chains",
    },
    {
      icon: TrendingUp,
      title: "Performance Insights",
      description: "AWS RDS Performance Insights equivalent for on-premise SQL Server",
    },
    {
      icon: Shield,
      title: "Self-Hosted & Secure",
      description: "Deploy on Azure, AWS, or on-premise. Your data never leaves your infrastructure",
    },
  ];

  const stats = [
    { label: "Production Servers", value: "3+", subtext: "Actively monitored" },
    { label: "Database Objects", value: "615", subtext: "Indexed in 250ms" },
    { label: "Data Retention", value: "90 days", subtext: "Configurable" },
    { label: "Cost Savings", value: "98%", subtext: "vs commercial solutions" },
  ];

  const comparisons = [
    { name: "SQL Monitor", price: "$0-$1,500/year", highlight: true },
    { name: "SentryOne", price: "$27,000/year", highlight: false },
    { name: "Redgate", price: "$32,000/year", highlight: false },
    { name: "SolarWinds", price: "$15,000/year", highlight: false },
  ];

  return (
    <>
      <Nav />
      <main className="flex-1">
        {/* Hero Section */}
        <section className="container mx-auto px-4 py-24 md:py-32">
          <div className="flex flex-col items-center text-center">
            <div className="mb-4 inline-flex items-center rounded-full border px-4 py-1.5 text-sm">
              <span className="text-primary">●</span>
              <span className="ml-2 text-muted-foreground">
                Open Source • Self-Hosted • Enterprise-Ready
              </span>
            </div>

            <h1 className="mb-6 text-4xl font-bold tracking-tight sm:text-6xl md:text-7xl">
              Enterprise SQL Server
              <br />
              <span className="text-primary">Monitoring Made Simple</span>
            </h1>

            <p className="mb-8 max-w-2xl text-lg text-muted-foreground sm:text-xl">
              Self-hosted, open source monitoring solution for SQL Server. Real-time metrics,
              automated alerting, and 23 pre-built Grafana dashboards.{" "}
              <span className="font-semibold text-foreground">
                $0-$1,500/year vs. $27k-$37k commercial solutions.
              </span>
            </p>

            <div className="flex flex-col gap-4 sm:flex-row">
              <Button asChild size="lg" className="text-base">
                <Link href="/docs">Get Started</Link>
              </Button>
              <Button asChild variant="outline" size="lg" className="text-base">
                <Link href="https://github.com/dbbuilder/sql-monitor" target="_blank">
                  View on GitHub
                </Link>
              </Button>
            </div>

            {/* Stats */}
            <div className="mt-20 grid w-full grid-cols-2 gap-8 md:grid-cols-4">
              {stats.map((stat) => (
                <div key={stat.label} className="flex flex-col items-center">
                  <div className="text-3xl font-bold text-primary md:text-4xl">{stat.value}</div>
                  <div className="mt-1 text-sm font-medium text-foreground">{stat.label}</div>
                  <div className="text-xs text-muted-foreground">{stat.subtext}</div>
                </div>
              ))}
            </div>
          </div>
        </section>

        {/* Features Section */}
        <section className="border-t bg-muted/50 py-24">
          <div className="container mx-auto px-4">
            <div className="mb-12 text-center">
              <h2 className="mb-4 text-3xl font-bold tracking-tight sm:text-4xl">
                Everything You Need
              </h2>
              <p className="mx-auto max-w-2xl text-lg text-muted-foreground">
                Comprehensive SQL Server monitoring without the enterprise price tag
              </p>
            </div>

            <div className="grid gap-6 md:grid-cols-2 lg:grid-cols-3">
              {features.map((feature) => {
                const Icon = feature.icon;
                return (
                  <Card key={feature.title}>
                    <CardHeader>
                      <div className="mb-2 flex h-12 w-12 items-center justify-center rounded-lg bg-primary/10">
                        <Icon className="h-6 w-6 text-primary" />
                      </div>
                      <CardTitle>{feature.title}</CardTitle>
                      <CardDescription>{feature.description}</CardDescription>
                    </CardHeader>
                  </Card>
                );
              })}
            </div>

            <div className="mt-12 text-center">
              <Button asChild variant="outline" size="lg">
                <Link href="/features">View All Features →</Link>
              </Button>
            </div>
          </div>
        </section>

        {/* Pricing Comparison */}
        <section className="py-24">
          <div className="container mx-auto px-4">
            <div className="mb-12 text-center">
              <h2 className="mb-4 text-3xl font-bold tracking-tight sm:text-4xl">
                Unbeatable Value
              </h2>
              <p className="mx-auto max-w-2xl text-lg text-muted-foreground">
                Get enterprise features without enterprise costs
              </p>
            </div>

            <div className="mx-auto grid max-w-3xl gap-4 md:grid-cols-4">
              {comparisons.map((item) => (
                <Card
                  key={item.name}
                  className={item.highlight ? "border-primary shadow-lg" : ""}
                >
                  <CardHeader className="text-center">
                    {item.highlight && (
                      <div className="mb-2">
                        <span className="inline-flex items-center rounded-full bg-primary px-3 py-1 text-xs font-medium text-primary-foreground">
                          Best Value
                        </span>
                      </div>
                    )}
                    <CardTitle className="text-lg">{item.name}</CardTitle>
                    <CardDescription>
                      <span className="text-2xl font-bold text-foreground">{item.price}</span>
                    </CardDescription>
                  </CardHeader>
                </Card>
              ))}
            </div>

            <div className="mt-12 text-center">
              <Button asChild size="lg">
                <Link href="/pricing">See Full Comparison →</Link>
              </Button>
            </div>
          </div>
        </section>

        {/* Key Benefits */}
        <section className="border-t bg-muted/50 py-24">
          <div className="container mx-auto px-4">
            <div className="mx-auto max-w-3xl">
              <h2 className="mb-12 text-center text-3xl font-bold tracking-tight sm:text-4xl">
                Why SQL Monitor?
              </h2>

              <div className="space-y-6">
                <Card>
                  <CardHeader>
                    <div className="flex items-start gap-4">
                      <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-primary/10">
                        <DollarSign className="h-5 w-5 text-primary" />
                      </div>
                      <div>
                        <CardTitle>98% Cost Savings</CardTitle>
                        <CardDescription className="mt-2">
                          Commercial solutions like SentryOne cost $27,000/year for 10 servers. SQL
                          Monitor is free for unlimited servers, with optional enterprise support at
                          $1,500/year.
                        </CardDescription>
                      </div>
                    </div>
                  </CardHeader>
                </Card>

                <Card>
                  <CardHeader>
                    <div className="flex items-start gap-4">
                      <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-primary/10">
                        <Cloud className="h-5 w-5 text-primary" />
                      </div>
                      <div>
                        <CardTitle>Deploy Anywhere</CardTitle>
                        <CardDescription className="mt-2">
                          Azure Container Instances, AWS ECS Fargate, on-premise Docker, or
                          Kubernetes. Your data stays in your infrastructure with zero vendor
                          lock-in.
                        </CardDescription>
                      </div>
                    </div>
                  </CardHeader>
                </Card>

                <Card>
                  <CardHeader>
                    <div className="flex items-start gap-4">
                      <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-primary/10">
                        <Clock className="h-5 w-5 text-primary" />
                      </div>
                      <div>
                        <CardTitle>5-Minute Setup</CardTitle>
                        <CardDescription className="mt-2">
                          Run database setup scripts, deploy Grafana container, configure
                          dashboards. No complex agents, no external dependencies, no lengthy
                          onboarding.
                        </CardDescription>
                      </div>
                    </div>
                  </CardHeader>
                </Card>

                <Card>
                  <CardHeader>
                    <div className="flex items-start gap-4">
                      <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-primary/10">
                        <CheckCircle2 className="h-5 w-5 text-primary" />
                      </div>
                      <div>
                        <CardTitle>Production-Tested</CardTitle>
                        <CardDescription className="mt-2">
                          Monitoring 3+ production SQL Servers with 615 database objects indexed
                          in 250ms. 90-day metrics retention with columnstore compression. Battle-tested at scale.
                        </CardDescription>
                      </div>
                    </div>
                  </CardHeader>
                </Card>
              </div>
            </div>
          </div>
        </section>

        {/* CTA Section */}
        <section className="border-t py-24">
          <div className="container mx-auto px-4 text-center">
            <h2 className="mb-4 text-3xl font-bold tracking-tight sm:text-4xl">
              Start Monitoring in 5 Minutes
            </h2>
            <p className="mx-auto mb-8 max-w-2xl text-lg text-muted-foreground">
              Clone the repository, run setup scripts, deploy the container. Open source, MIT
              licensed, forever free.
            </p>
            <div className="flex flex-col gap-4 sm:flex-row sm:justify-center">
              <Button asChild size="lg">
                <Link href="/docs">Read Documentation</Link>
              </Button>
              <Button asChild variant="outline" size="lg">
                <Link href="https://github.com/dbbuilder/sql-monitor" target="_blank">
                  Clone Repository
                </Link>
              </Button>
              <Button asChild variant="outline" size="lg">
                <Link href="/contact">Contact Sales</Link>
              </Button>
            </div>
          </div>
        </section>
      </main>
      <Footer />
    </>
  );
}
