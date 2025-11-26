"use client";

import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Loader2, CheckCircle2, AlertCircle } from "lucide-react";

export function ContactForm() {
  const [formData, setFormData] = useState({
    name: "",
    email: "",
    company: "",
    message: "",
  });
  const [status, setStatus] = useState<"idle" | "loading" | "success" | "error">("idle");
  const [errorMessage, setErrorMessage] = useState("");

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setStatus("loading");
    setErrorMessage("");

    try {
      const response = await fetch("/api/contact", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify(formData),
      });

      const data = await response.json();

      if (!response.ok) {
        throw new Error(data.error || "Failed to send message");
      }

      setStatus("success");
      setFormData({ name: "", email: "", company: "", message: "" });
    } catch (error) {
      setStatus("error");
      setErrorMessage(error instanceof Error ? error.message : "Failed to send message");
    }
  };

  const handleChange = (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) => {
    setFormData((prev) => ({
      ...prev,
      [e.target.name]: e.target.value,
    }));
  };

  return (
    <Card>
      <CardHeader>
        <CardTitle>Send us a message</CardTitle>
        <CardDescription>
          We&apos;ll get back to you within 24 hours. For urgent issues, please use GitHub Issues.
        </CardDescription>
      </CardHeader>
      <CardContent>
        {status === "success" ? (
          <div className="flex flex-col items-center justify-center py-8 text-center">
            <CheckCircle2 className="mb-4 h-12 w-12 text-primary" />
            <h3 className="mb-2 text-lg font-semibold">Message sent successfully!</h3>
            <p className="mb-4 text-sm text-muted-foreground">
              We&apos;ll get back to you at {formData.email} within 24 hours.
            </p>
            <Button onClick={() => setStatus("idle")} variant="outline">
              Send another message
            </Button>
          </div>
        ) : (
          <form onSubmit={handleSubmit} className="space-y-4">
            {status === "error" && (
              <div className="flex items-center gap-2 rounded-lg border border-destructive bg-destructive/10 p-3 text-sm text-destructive">
                <AlertCircle className="h-4 w-4" />
                <span>{errorMessage}</span>
              </div>
            )}

            <div className="space-y-2">
              <Label htmlFor="name">Name *</Label>
              <Input
                id="name"
                name="name"
                value={formData.name}
                onChange={handleChange}
                required
                placeholder="John Doe"
                disabled={status === "loading"}
              />
            </div>

            <div className="space-y-2">
              <Label htmlFor="email">Email *</Label>
              <Input
                id="email"
                name="email"
                type="email"
                value={formData.email}
                onChange={handleChange}
                required
                placeholder="john@example.com"
                disabled={status === "loading"}
              />
            </div>

            <div className="space-y-2">
              <Label htmlFor="company">Company</Label>
              <Input
                id="company"
                name="company"
                value={formData.company}
                onChange={handleChange}
                placeholder="Acme Corp"
                disabled={status === "loading"}
              />
            </div>

            <div className="space-y-2">
              <Label htmlFor="message">Message *</Label>
              <Textarea
                id="message"
                name="message"
                value={formData.message}
                onChange={handleChange}
                required
                placeholder="Tell us about your needs or questions..."
                rows={6}
                disabled={status === "loading"}
              />
            </div>

            <Button type="submit" className="w-full" disabled={status === "loading"}>
              {status === "loading" ? (
                <>
                  <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                  Sending...
                </>
              ) : (
                "Send Message"
              )}
            </Button>
          </form>
        )}
      </CardContent>
    </Card>
  );
}
