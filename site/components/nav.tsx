"use client";

import Link from "next/link";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Menu, X, Github } from "lucide-react";

export function Nav() {
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false);

  const navigation = [
    { name: "Features", href: "/features" },
    { name: "Pricing", href: "/pricing" },
    { name: "Docs", href: "/docs" },
    { name: "Contact", href: "/contact" },
  ];

  return (
    <nav className="sticky top-0 z-50 w-full border-b bg-background/95 backdrop-blur supports-[backdrop-filter]:bg-background/60">
      <div className="container mx-auto px-4">
        <div className="flex h-16 items-center justify-between">
          {/* Logo */}
          <Link href="/" className="flex items-center space-x-2">
            <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-primary">
              <span className="text-lg font-bold text-primary-foreground">S</span>
            </div>
            <span className="text-xl font-bold">SQL Monitor</span>
          </Link>

          {/* Desktop Navigation */}
          <div className="hidden md:flex md:items-center md:space-x-8">
            {navigation.map((item) => (
              <Link
                key={item.name}
                href={item.href}
                className="text-sm font-medium text-muted-foreground transition-colors hover:text-foreground"
              >
                {item.name}
              </Link>
            ))}
            <Button asChild variant="ghost" size="sm">
              <Link
                href="https://github.com/dbbuilder/sql-monitor"
                target="_blank"
                rel="noopener noreferrer"
                className="flex items-center gap-2"
              >
                <Github className="h-4 w-4" />
                GitHub
              </Link>
            </Button>
            <Button asChild size="sm">
              <Link href="/docs">Get Started</Link>
            </Button>
          </div>

          {/* Mobile menu button */}
          <div className="flex md:hidden">
            <Button
              variant="ghost"
              size="sm"
              onClick={() => setMobileMenuOpen(!mobileMenuOpen)}
            >
              {mobileMenuOpen ? (
                <X className="h-6 w-6" />
              ) : (
                <Menu className="h-6 w-6" />
              )}
            </Button>
          </div>
        </div>
      </div>

      {/* Mobile menu */}
      {mobileMenuOpen && (
        <div className="md:hidden">
          <div className="space-y-1 px-4 pb-3 pt-2">
            {navigation.map((item) => (
              <Link
                key={item.name}
                href={item.href}
                className="block rounded-md px-3 py-2 text-base font-medium text-muted-foreground hover:bg-accent hover:text-foreground"
                onClick={() => setMobileMenuOpen(false)}
              >
                {item.name}
              </Link>
            ))}
            <Link
              href="https://github.com/dbbuilder/sql-monitor"
              target="_blank"
              rel="noopener noreferrer"
              className="flex items-center gap-2 rounded-md px-3 py-2 text-base font-medium text-muted-foreground hover:bg-accent hover:text-foreground"
              onClick={() => setMobileMenuOpen(false)}
            >
              <Github className="h-4 w-4" />
              GitHub
            </Link>
            <div className="px-3 py-2">
              <Button asChild className="w-full">
                <Link href="/docs" onClick={() => setMobileMenuOpen(false)}>
                  Get Started
                </Link>
              </Button>
            </div>
          </div>
        </div>
      )}
    </nav>
  );
}
