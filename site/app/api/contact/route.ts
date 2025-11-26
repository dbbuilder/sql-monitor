import { NextResponse } from "next/server";
import { Resend } from "resend";
import { z } from "zod";

// Initialize Resend client (use placeholder during build)
const resend = new Resend(process.env.RESEND_API_KEY || "placeholder");

const contactSchema = z.object({
  name: z.string().min(2, "Name must be at least 2 characters"),
  email: z.string().email("Invalid email address"),
  company: z.string().optional(),
  message: z.string().min(10, "Message must be at least 10 characters"),
});

export async function POST(request: Request) {
  try {
    // Check for API key at runtime
    if (!process.env.RESEND_API_KEY || process.env.RESEND_API_KEY === "placeholder") {
      return NextResponse.json(
        { error: "Email service not configured. Please contact us at info@servicevision.net" },
        { status: 503 }
      );
    }

    const body = await request.json();

    // Validate input
    const validated = contactSchema.parse(body);

    // Send email via Resend
    const { data, error } = await resend.emails.send({
      from: "SQL Monitor <noreply@sqlmonitor.servicevision.net>",
      to: process.env.NEXT_PUBLIC_CONTACT_EMAIL || "info@servicevision.net",
      replyTo: validated.email,
      subject: `SQL Monitor Contact: ${validated.name}${validated.company ? ` from ${validated.company}` : ""}`,
      html: `
        <!DOCTYPE html>
        <html>
          <head>
            <meta charset="utf-8">
            <style>
              body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; line-height: 1.6; color: #333; }
              .container { max-width: 600px; margin: 0 auto; padding: 20px; }
              .header { background-color: #1976D2; color: white; padding: 20px; border-radius: 8px 8px 0 0; }
              .content { background-color: #f5f5f5; padding: 30px; border-radius: 0 0 8px 8px; }
              .field { margin-bottom: 20px; }
              .label { font-weight: 600; color: #666; font-size: 12px; text-transform: uppercase; margin-bottom: 5px; }
              .value { font-size: 16px; color: #333; }
              .message { background-color: white; padding: 15px; border-radius: 4px; border-left: 4px solid #1976D2; }
              .footer { margin-top: 30px; padding-top: 20px; border-top: 2px solid #ddd; font-size: 12px; color: #666; }
            </style>
          </head>
          <body>
            <div class="container">
              <div class="header">
                <h1 style="margin: 0; font-size: 24px;">New Contact Form Submission</h1>
                <p style="margin: 10px 0 0 0; opacity: 0.9;">SQL Monitor Website</p>
              </div>
              <div class="content">
                <div class="field">
                  <div class="label">Name</div>
                  <div class="value">${validated.name}</div>
                </div>

                <div class="field">
                  <div class="label">Email</div>
                  <div class="value"><a href="mailto:${validated.email}">${validated.email}</a></div>
                </div>

                ${
                  validated.company
                    ? `
                <div class="field">
                  <div class="label">Company</div>
                  <div class="value">${validated.company}</div>
                </div>
                `
                    : ""
                }

                <div class="field">
                  <div class="label">Message</div>
                  <div class="message">${validated.message.replace(/\n/g, "<br>")}</div>
                </div>

                <div class="footer">
                  <p>This email was sent from the SQL Monitor contact form at ${process.env.NEXT_PUBLIC_SITE_URL || "https://sqlmonitor.servicevision.net"}</p>
                  <p>To respond, simply reply to this email or contact ${validated.email} directly.</p>
                </div>
              </div>
            </div>
          </body>
        </html>
      `,
    });

    if (error) {
      console.error("Resend error:", error);
      return NextResponse.json({ error: error.message || "Failed to send email" }, { status: 500 });
    }

    return NextResponse.json({ success: true, id: data?.id }, { status: 200 });
  } catch (error) {
    console.error("Contact form error:", error);

    if (error instanceof z.ZodError) {
      return NextResponse.json(
        { error: "Validation error", details: error.errors },
        { status: 400 }
      );
    }

    return NextResponse.json(
      { error: "Failed to send message. Please try again later." },
      { status: 500 }
    );
  }
}
