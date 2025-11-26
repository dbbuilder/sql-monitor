import { Nav } from "@/components/nav";
import { Footer } from "@/components/footer";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import Link from "next/link";
import { Check, X } from "lucide-react";
import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Pricing - SQL Monitor",
  description: "SQL Monitor pricing: Free community edition, $99/month professional, $199/month hosted, or $1,500/year enterprise. 98% cheaper than commercial solutions.",
};

export default function PricingPage() {
  const plans = [
    {
      name: "Community Edition",
      price: "$0",
      period: "forever",
      description: "Perfect for teams who want full monitoring capabilities",
      features: [
        "Unlimited SQL Server instances",
        "All features included",
        "23 Grafana dashboards",
        "T-SQL Code Editor",
        "Automated alerting",
        "PDF/PNG export",
        "90-day metrics retention",
        "Community support via GitHub",
        "MIT/Apache 2.0 open source",
        "Self-hosted deployment",
        "Azure, AWS, On-Premise",
        "Regular updates from GitHub",
      ],
      cta: "Get Started",
      ctaLink: "/docs",
      highlighted: false,
    },
    {
      name: "Professional",
      price: "$99",
      period: "per month",
      description: "Self-hosted with support and full commercial license",
      features: [
        "Everything in Community Edition",
        "Deploy on your infrastructure",
        "On-premise or your cloud",
        "Full commercial license",
        "Email support (48hr response)",
        "Installation assistance",
        "Upgrade guidance",
        "Security updates",
        "Quarterly check-ins",
        "Documentation access",
        "Best practices guide",
        "No data sharing required",
      ],
      cta: "Start Trial",
      ctaLink: "/contact",
      highlighted: false,
    },
    {
      name: "Hosted",
      price: "$199",
      period: "per month",
      description: "Fully managed monitoring hosted by us",
      features: [
        "Everything in Professional",
        "We host everything for you",
        "No infrastructure required",
        "Automatic updates",
        "Daily backups",
        "24/7 monitoring",
        "99.9% uptime SLA",
        "Priority support (24hr response)",
        "Dedicated monitoring instance",
        "Secure data storage",
        "Custom subdomain",
        "Free SSL certificate",
      ],
      cta: "Contact Sales",
      ctaLink: "/contact",
      highlighted: true,
    },
    {
      name: "Enterprise",
      price: "$1,500",
      period: "per year",
      description: "Premium support and custom development for any tier",
      features: [
        "Add to any plan above",
        "Priority support (4hr response)",
        "Custom dashboard development",
        "Migration assistance",
        "Training sessions (4 hours/year)",
        "Architecture consultation",
        "Performance tuning guidance",
        "Quarterly business reviews",
        "Direct access to engineering team",
        "Feature prioritization",
        "Annual health check",
        "Dedicated Slack channel",
      ],
      cta: "Contact Sales",
      ctaLink: "/contact",
      highlighted: false,
    },
  ];

  const comparison = {
    headers: ["Feature", "SQL Monitor", "SentryOne", "Redgate", "SolarWinds"],
    rows: [
      {
        feature: "Price (10 servers/year)",
        values: ["$0-$2,388", "$27,000", "$32,000", "$15,000"],
        highlight: [true, false, false, false],
      },
      {
        feature: "Price (50 servers/year)",
        values: ["$0-$2,388", "$75,000+", "$90,000+", "$45,000+"],
        highlight: [true, false, false, false],
      },
      {
        feature: "Self-Hosted",
        values: ["✓", "✓", "✗", "✓"],
        highlight: [false, false, false, false],
      },
      {
        feature: "Open Source",
        values: ["✓", "✗", "✗", "✗"],
        highlight: [true, false, false, false],
      },
      {
        feature: "Cloud Lock-In",
        values: ["None", "None", "Azure Only", "None"],
        highlight: [true, false, false, false],
      },
      {
        feature: "Custom Dashboards",
        values: ["Unlimited", "Limited", "Limited", "Limited"],
        highlight: [true, false, false, false],
      },
      {
        feature: "Data Retention",
        values: ["90 days (configurable)", "30 days", "7 days", "30 days"],
        highlight: [true, false, false, false],
      },
      {
        feature: "Alerting",
        values: ["✓", "✓", "✓", "✓"],
        highlight: [false, false, false, false],
      },
      {
        feature: "Query Store Integration",
        values: ["✓", "✓", "✓", "✓"],
        highlight: [false, false, false, false],
      },
      {
        feature: "Code Editor",
        values: ["✓ (30+ rules)", "✗", "✗", "✗"],
        highlight: [true, false, false, false],
      },
      {
        feature: "PDF Export",
        values: ["✓", "✓", "✓", "✓"],
        highlight: [false, false, false, false],
      },
      {
        feature: "API Access",
        values: ["✓ (Full REST API)", "Limited", "Limited", "Limited"],
        highlight: [true, false, false, false],
      },
      {
        feature: "Multi-Cloud Support",
        values: ["Azure, AWS, GCP, On-Prem", "Azure, On-Prem", "Azure Only", "Azure, AWS, On-Prem"],
        highlight: [true, false, false, false],
      },
    ],
  };

  const faqs = [
    {
      question: "Is SQL Monitor really free?",
      answer:
        "Yes! The Community Edition is completely free, open source (MIT/Apache 2.0 licenses), and includes all features for unlimited SQL Server instances. There are no hidden costs, no per-server fees, and no feature limitations. Enterprise Support is optional for organizations that need dedicated support and custom development.",
    },
    {
      question: "What's the difference between Professional and Hosted?",
      answer:
        "Professional ($99/mo) is self-hosted on your infrastructure with support and a commercial license. You deploy and manage it on your servers or cloud. Hosted ($199/mo) is fully managed by us - we handle hosting, updates, backups, and monitoring. Choose Professional if you want control and lower cost, or Hosted if you want zero infrastructure management.",
    },
    {
      question: "What's included in Enterprise Support?",
      answer:
        "Enterprise Support ($1,500/year) can be added to any tier for priority support (4hr response), custom dashboard development, migration assistance, 4 hours of training per year, architecture consultation, performance tuning guidance, quarterly business reviews, and direct access to our engineering team. Perfect for organizations with complex requirements.",
    },
    {
      question: "How does this compare to SentryOne or Redgate?",
      answer:
        "SQL Monitor provides the same core monitoring capabilities at 98% lower cost. SentryOne costs $27,000/year for 10 servers and Redgate costs $32,000/year. SQL Monitor starts free, or $1,188-$2,388/year for Professional/Hosted tiers with unlimited servers. Plus, you own your data and deployment infrastructure with zero vendor lock-in.",
    },
    {
      question: "Can I deploy to Azure, AWS, or on-premise?",
      answer:
        "Yes! SQL Monitor supports Azure Container Instances, AWS ECS Fargate, GCP Cloud Run, on-premise Docker, and Kubernetes. Deploy wherever your infrastructure lives with no vendor lock-in. The same Docker image works everywhere.",
    },
    {
      question: "What if I need custom dashboards or features?",
      answer:
        "With the Community Edition, you can create unlimited custom Grafana dashboards and modify the source code (MIT/Apache 2.0 licenses). With Enterprise Support, our team will build custom dashboards for you and prioritize feature requests. You can also hire us for custom development work.",
    },
    {
      question: "Do you offer discounts for non-profits or educational institutions?",
      answer:
        "The Community Edition is already free for everyone! For Enterprise Support, we offer 50% discounts to qualified non-profits and educational institutions. Contact us at info@servicevision.net to discuss your needs.",
    },
    {
      question: "What's the total cost of ownership?",
      answer:
        "Community (self-hosted): $0-$696/year depending on cloud infrastructure. Professional: $1,188/year + your infrastructure costs. Hosted: $2,388/year (we handle everything). Add $1,500/year for Enterprise Support if needed. Compare this to $27k-$37k/year for commercial solutions - that's 90-98% savings.",
    },
    {
      question: "Can I upgrade or downgrade between tiers?",
      answer:
        "Yes, absolutely! There are no long-term contracts. You can upgrade from Community to Professional or Hosted at any time. You can also downgrade or cancel with 30 days notice. Enterprise Support is annual but can be added or removed yearly. Your monitoring data and configuration are always portable.",
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
              Simple, Transparent Pricing
            </h1>
            <p className="mx-auto max-w-2xl text-lg text-muted-foreground">
              98% cheaper than commercial solutions. Start free, upgrade to Professional ($99/mo), Hosted ($199/mo), or Enterprise ($1,500/yr).
            </p>
          </div>
        </section>

        {/* Pricing Cards */}
        <section className="py-20">
          <div className="container mx-auto px-4">
            <div className="mx-auto grid max-w-7xl gap-6 md:grid-cols-2 xl:grid-cols-4">
              {plans.map((plan) => (
                <Card
                  key={plan.name}
                  className={plan.highlighted ? "border-primary shadow-xl" : ""}
                >
                  <CardHeader>
                    {plan.highlighted && (
                      <div className="mb-2">
                        <span className="inline-flex items-center rounded-full bg-primary px-3 py-1 text-xs font-medium text-primary-foreground">
                          Most Popular
                        </span>
                      </div>
                    )}
                    <CardTitle className="text-2xl">{plan.name}</CardTitle>
                    <CardDescription>{plan.description}</CardDescription>
                    <div className="mt-4">
                      <span className="text-4xl font-bold">{plan.price}</span>
                      <span className="text-muted-foreground">/{plan.period}</span>
                    </div>
                  </CardHeader>
                  <CardContent>
                    <ul className="mb-6 space-y-3">
                      {plan.features.map((feature) => (
                        <li key={feature} className="flex items-start gap-2">
                          <Check className="mt-0.5 h-5 w-5 flex-shrink-0 text-primary" />
                          <span className="text-sm">{feature}</span>
                        </li>
                      ))}
                    </ul>
                    <Button asChild className="w-full" size="lg" variant={plan.highlighted ? "default" : "outline"}>
                      <Link href={plan.ctaLink}>{plan.cta}</Link>
                    </Button>
                  </CardContent>
                </Card>
              ))}
            </div>
          </div>
        </section>

        {/* Comparison Table */}
        <section className="border-t bg-muted/50 py-20">
          <div className="container mx-auto px-4">
            <h2 className="mb-4 text-center text-3xl font-bold">Feature Comparison</h2>
            <p className="mb-12 text-center text-lg text-muted-foreground">
              See how SQL Monitor stacks up against commercial solutions
            </p>

            <div className="mx-auto max-w-6xl overflow-x-auto">
              <table className="w-full border-collapse">
                <thead>
                  <tr className="border-b">
                    {comparison.headers.map((header, index) => (
                      <th
                        key={header}
                        className={`p-4 text-left font-semibold ${
                          index === 0 ? "w-1/4" : "w-[18.75%]"
                        } ${index === 1 ? "bg-primary/5" : ""}`}
                      >
                        {header}
                      </th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {comparison.rows.map((row, rowIndex) => (
                    <tr key={row.feature} className="border-b">
                      <td className="p-4 font-medium">{row.feature}</td>
                      {row.values.map((value, colIndex) => (
                        <td
                          key={colIndex}
                          className={`p-4 ${colIndex === 0 ? "bg-primary/5" : ""} ${
                            row.highlight[colIndex] ? "font-semibold text-primary" : ""
                          }`}
                        >
                          {value}
                        </td>
                      ))}
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        </section>

        {/* FAQs */}
        <section className="border-t py-20">
          <div className="container mx-auto px-4">
            <h2 className="mb-12 text-center text-3xl font-bold">Frequently Asked Questions</h2>
            <div className="mx-auto max-w-3xl space-y-6">
              {faqs.map((faq) => (
                <Card key={faq.question}>
                  <CardHeader>
                    <CardTitle className="text-lg">{faq.question}</CardTitle>
                  </CardHeader>
                  <CardContent>
                    <p className="text-muted-foreground">{faq.answer}</p>
                  </CardContent>
                </Card>
              ))}
            </div>
          </div>
        </section>

        {/* CTA */}
        <section className="border-t bg-muted/50 py-20">
          <div className="container mx-auto px-4 text-center">
            <h2 className="mb-4 text-3xl font-bold">Ready to Save 90-98% on Monitoring Costs?</h2>
            <p className="mx-auto mb-8 max-w-2xl text-lg text-muted-foreground">
              Start with the free Community Edition, upgrade to Professional/Hosted, or contact us for Enterprise Support
            </p>
            <div className="flex flex-col gap-4 sm:flex-row sm:justify-center">
              <Button asChild size="lg">
                <Link href="/docs">Get Started Free</Link>
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
