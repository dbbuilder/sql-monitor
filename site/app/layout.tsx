import type { Metadata } from "next";
import { Inter } from "next/font/google";
import "./globals.css";
import { cn } from "@/lib/utils";

const inter = Inter({ subsets: ["latin"] });

export const metadata: Metadata = {
  title: "SQL Monitor - Self-Hosted SQL Server Monitoring",
  description: "Enterprise-grade SQL Server monitoring solution. Self-hosted, open source, and designed for performance. Monitor multiple SQL Server instances with real-time metrics, alerting, and automated recommendations.",
  keywords: ["SQL Server", "monitoring", "performance", "database", "self-hosted", "open source", "DevOps", "DBA"],
  authors: [{ name: "ServiceVision" }],
  creator: "ServiceVision",
  publisher: "ServiceVision",
  metadataBase: new URL(process.env.NEXT_PUBLIC_SITE_URL || "https://sqlmonitor.servicevision.net"),
  openGraph: {
    type: "website",
    locale: "en_US",
    url: process.env.NEXT_PUBLIC_SITE_URL || "https://sqlmonitor.servicevision.net",
    title: "SQL Monitor - Self-Hosted SQL Server Monitoring",
    description: "Enterprise-grade SQL Server monitoring solution. Self-hosted, open source, and designed for performance.",
    siteName: "SQL Monitor",
  },
  twitter: {
    card: "summary_large_image",
    title: "SQL Monitor - Self-Hosted SQL Server Monitoring",
    description: "Enterprise-grade SQL Server monitoring solution. Self-hosted, open source, and designed for performance.",
  },
  robots: {
    index: true,
    follow: true,
    googleBot: {
      index: true,
      follow: true,
      "max-video-preview": -1,
      "max-image-preview": "large",
      "max-snippet": -1,
    },
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" suppressHydrationWarning>
      <body className={cn(inter.className, "min-h-screen bg-background antialiased")}>
        {children}
      </body>
    </html>
  );
}
