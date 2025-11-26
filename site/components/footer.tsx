import Link from "next/link";
import { Github } from "lucide-react";

export function Footer() {
  const currentYear = new Date().getFullYear();

  return (
    <footer className="border-t bg-background">
      <div className="container mx-auto px-4 py-12">
        <div className="grid grid-cols-1 gap-8 md:grid-cols-4">
          {/* Company */}
          <div>
            <div className="flex items-center space-x-2 mb-4">
              <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-primary">
                <span className="text-lg font-bold text-primary-foreground">S</span>
              </div>
              <span className="text-xl font-bold">SQL Monitor</span>
            </div>
            <p className="text-sm text-muted-foreground">
              Enterprise-grade SQL Server monitoring. Self-hosted, open source, and designed for performance.
            </p>
          </div>

          {/* Product */}
          <div>
            <h3 className="mb-4 text-sm font-semibold">Product</h3>
            <ul className="space-y-3 text-sm">
              <li>
                <Link href="/features" className="text-muted-foreground hover:text-foreground">
                  Features
                </Link>
              </li>
              <li>
                <Link href="/pricing" className="text-muted-foreground hover:text-foreground">
                  Pricing
                </Link>
              </li>
              <li>
                <Link href="/docs" className="text-muted-foreground hover:text-foreground">
                  Documentation
                </Link>
              </li>
              <li>
                <Link
                  href="https://github.com/dbbuilder/sql-monitor"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-muted-foreground hover:text-foreground"
                >
                  GitHub
                </Link>
              </li>
            </ul>
          </div>

          {/* Resources */}
          <div>
            <h3 className="mb-4 text-sm font-semibold">Resources</h3>
            <ul className="space-y-3 text-sm">
              <li>
                <Link href="/docs#quickstart" className="text-muted-foreground hover:text-foreground">
                  Quick Start
                </Link>
              </li>
              <li>
                <Link href="/docs#deployment" className="text-muted-foreground hover:text-foreground">
                  Deployment Guides
                </Link>
              </li>
              <li>
                <Link
                  href="https://github.com/dbbuilder/sql-monitor/issues"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-muted-foreground hover:text-foreground"
                >
                  GitHub Issues
                </Link>
              </li>
              <li>
                <Link href="/contact" className="text-muted-foreground hover:text-foreground">
                  Contact Support
                </Link>
              </li>
            </ul>
          </div>

          {/* Company */}
          <div>
            <h3 className="mb-4 text-sm font-semibold">Company</h3>
            <ul className="space-y-3 text-sm">
              <li>
                <Link href="/contact" className="text-muted-foreground hover:text-foreground">
                  Contact
                </Link>
              </li>
              <li>
                <a
                  href="mailto:info@servicevision.net"
                  className="text-muted-foreground hover:text-foreground"
                >
                  info@servicevision.net
                </a>
              </li>
              <li>
                <Link
                  href="https://github.com/dbbuilder/sql-monitor"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="flex items-center gap-2 text-muted-foreground hover:text-foreground"
                >
                  <Github className="h-4 w-4" />
                  Follow on GitHub
                </Link>
              </li>
            </ul>
          </div>
        </div>

        <div className="mt-12 border-t pt-8">
          <div className="flex flex-col items-center justify-between gap-4 md:flex-row">
            <p className="text-sm text-muted-foreground">
              © {currentYear} ServiceVision. All rights reserved.
            </p>
            <div className="flex gap-6 text-sm text-muted-foreground">
              <Link href="/docs#license" className="hover:text-foreground">
                MIT License
              </Link>
              <span>•</span>
              <Link href="/docs#privacy" className="hover:text-foreground">
                Privacy
              </Link>
              <span>•</span>
              <Link href="/docs#terms" className="hover:text-foreground">
                Terms
              </Link>
            </div>
          </div>
        </div>
      </div>
    </footer>
  );
}
