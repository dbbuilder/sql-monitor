import { Nav } from "@/components/nav";
import { Footer } from "@/components/footer";
import { ContactForm } from "@/components/contact-form";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Mail, Github, MessageSquare } from "lucide-react";
import Link from "next/link";
import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Contact - SQL Monitor",
  description: "Get in touch with the SQL Monitor team. Email us at info@servicevision.net or use our contact form.",
};

export default function ContactPage() {
  return (
    <>
      <Nav />
      <main className="flex-1">
        {/* Hero */}
        <section className="border-b bg-muted/50 py-20">
          <div className="container mx-auto px-4 text-center">
            <h1 className="mb-4 text-4xl font-bold tracking-tight sm:text-5xl">Get in Touch</h1>
            <p className="mx-auto max-w-2xl text-lg text-muted-foreground">
              Have questions about SQL Monitor? Need help with deployment? Want to discuss
              enterprise support? We&apos;re here to help.
            </p>
          </div>
        </section>

        {/* Contact Form & Info */}
        <section className="py-20">
          <div className="container mx-auto px-4">
            <div className="mx-auto grid max-w-5xl gap-8 lg:grid-cols-2">
              {/* Form */}
              <div>
                <ContactForm />
              </div>

              {/* Contact Info */}
              <div className="space-y-6">
                <Card>
                  <CardHeader>
                    <CardTitle className="flex items-center gap-2">
                      <Mail className="h-5 w-5 text-primary" />
                      Email Us
                    </CardTitle>
                  </CardHeader>
                  <CardContent>
                    <p className="mb-2 text-sm text-muted-foreground">
                      Send us an email for general inquiries or enterprise support
                    </p>
                    <a
                      href="mailto:info@servicevision.net"
                      className="text-lg font-medium text-primary hover:underline"
                    >
                      info@servicevision.net
                    </a>
                    <p className="mt-4 text-xs text-muted-foreground">
                      Response time: Within 24 hours (business days)
                    </p>
                  </CardContent>
                </Card>

                <Card>
                  <CardHeader>
                    <CardTitle className="flex items-center gap-2">
                      <Github className="h-5 w-5 text-primary" />
                      GitHub Issues
                    </CardTitle>
                  </CardHeader>
                  <CardContent>
                    <p className="mb-4 text-sm text-muted-foreground">
                      Found a bug? Have a feature request? Open an issue on GitHub
                    </p>
                    <Link
                      href="https://github.com/dbbuilder/sql-monitor/issues"
                      target="_blank"
                      rel="noopener noreferrer"
                      className="text-sm font-medium text-primary hover:underline"
                    >
                      View Issues →
                    </Link>
                  </CardContent>
                </Card>

                <Card>
                  <CardHeader>
                    <CardTitle className="flex items-center gap-2">
                      <MessageSquare className="h-5 w-5 text-primary" />
                      Community Support
                    </CardTitle>
                  </CardHeader>
                  <CardContent>
                    <p className="mb-4 text-sm text-muted-foreground">
                      Get help from the community through GitHub Discussions
                    </p>
                    <Link
                      href="https://github.com/dbbuilder/sql-monitor/discussions"
                      target="_blank"
                      rel="noopener noreferrer"
                      className="text-sm font-medium text-primary hover:underline"
                    >
                      Join Discussions →
                    </Link>
                  </CardContent>
                </Card>

                <Card className="border-primary/50 bg-primary/5">
                  <CardHeader>
                    <CardTitle>Enterprise Support</CardTitle>
                    <CardDescription>
                      Need priority support, custom development, or training?
                    </CardDescription>
                  </CardHeader>
                  <CardContent>
                    <p className="mb-4 text-sm">
                      Our Enterprise Support plan includes:
                    </p>
                    <ul className="mb-4 space-y-2 text-sm">
                      <li className="flex items-start">
                        <span className="mr-2 text-primary">•</span>
                        <span>Priority email & Teams support</span>
                      </li>
                      <li className="flex items-start">
                        <span className="mr-2 text-primary">•</span>
                        <span>Custom dashboard development</span>
                      </li>
                      <li className="flex items-start">
                        <span className="mr-2 text-primary">•</span>
                        <span>Migration assistance</span>
                      </li>
                      <li className="flex items-start">
                        <span className="mr-2 text-primary">•</span>
                        <span>4 hours of training per year</span>
                      </li>
                      <li className="flex items-start">
                        <span className="mr-2 text-primary">•</span>
                        <span>99.9% uptime SLA</span>
                      </li>
                    </ul>
                    <p className="text-sm font-medium">
                      $1,500/year{" "}
                      <span className="text-muted-foreground">
                        (vs. $27k-$37k commercial solutions)
                      </span>
                    </p>
                  </CardContent>
                </Card>
              </div>
            </div>
          </div>
        </section>

        {/* FAQs */}
        <section className="border-t bg-muted/50 py-20">
          <div className="container mx-auto px-4">
            <h2 className="mb-8 text-center text-3xl font-bold">Common Questions</h2>
            <div className="mx-auto max-w-3xl space-y-6">
              <Card>
                <CardHeader>
                  <CardTitle className="text-lg">How quickly can I expect a response?</CardTitle>
                </CardHeader>
                <CardContent>
                  <p className="text-sm text-muted-foreground">
                    We respond to all inquiries within 24 hours during business days (Monday-Friday).
                    Enterprise Support customers receive priority response within 4 hours.
                  </p>
                </CardContent>
              </Card>

              <Card>
                <CardHeader>
                  <CardTitle className="text-lg">
                    Can you help with migration from SentryOne or Redgate?
                  </CardTitle>
                </CardHeader>
                <CardContent>
                  <p className="text-sm text-muted-foreground">
                    Yes! We offer migration assistance as part of our Enterprise Support plan. We&apos;ll
                    help you transition from commercial monitoring solutions to SQL Monitor, including
                    dashboard recreation and custom development.
                  </p>
                </CardContent>
              </Card>

              <Card>
                <CardHeader>
                  <CardTitle className="text-lg">Do you offer training sessions?</CardTitle>
                </CardHeader>
                <CardContent>
                  <p className="text-sm text-muted-foreground">
                    Enterprise Support includes 4 hours of training per year. We cover deployment,
                    dashboard customization, query optimization, and best practices. Additional training
                    can be purchased separately.
                  </p>
                </CardContent>
              </Card>

              <Card>
                <CardHeader>
                  <CardTitle className="text-lg">
                    What if I need custom features or dashboards?
                  </CardTitle>
                </CardHeader>
                <CardContent>
                  <p className="text-sm text-muted-foreground">
                    Custom development is available for Enterprise Support customers. We can build
                    custom dashboards, integrate with your existing tools, or add new monitoring
                    capabilities specific to your environment.
                  </p>
                </CardContent>
              </Card>
            </div>
          </div>
        </section>
      </main>
      <Footer />
    </>
  );
}
