# SQL Monitor - Marketing Site

Next.js 14 marketing site for SQL Monitor with Tailwind CSS, shadcn/ui, and SEO optimization.

## Quick Start

```bash
# Install dependencies
npm install

# Run development server
npm run dev

# Build for production
npm run build

# Start production server
npm start
```

Visit: http://localhost:3000

## Project Structure

```
site/
├── app/                          # Next.js 14 App Router
│   ├── layout.tsx                # Root layout with SEO metadata
│   ├── page.tsx                  # Home page (TO CREATE)
│   ├── features/page.tsx         # Features page (TO CREATE)
│   ├── pricing/page.tsx          # Pricing page (TO CREATE)
│   ├── docs/page.tsx             # Documentation page (TO CREATE)
│   ├── contact/page.tsx          # Contact page (TO CREATE)
│   ├── api/
│   │   └── contact/route.ts      # Contact form API endpoint (TO CREATE)
│   └── globals.css               # Global styles + Tailwind
├── components/
│   ├── nav.tsx                   # Navigation component (TO CREATE)
│   ├── footer.tsx                # Footer component (TO CREATE)
│   ├── contact-form.tsx          # Contact form component (TO CREATE)
│   └── ui/                       # shadcn/ui components
│       ├── button.tsx            ✅ Created
│       ├── card.tsx              ✅ Created
│       ├── input.tsx             ✅ Created
│       ├── label.tsx             ✅ Created
│       └── textarea.tsx          ✅ Created
├── lib/
│   └── utils.ts                  # Utility functions (cn helper)
├── public/                       # Static assets
│   ├── logo.svg                  # (TO ADD)
│   └── screenshots/              # (TO ADD)
├── scripts/
│   └── update-dns.ts             # name.com DNS automation (TO CREATE)
├── package.json                  ✅ Created
├── tsconfig.json                 ✅ Created
├── next.config.mjs               ✅ Created
├── tailwind.config.ts            ✅ Created
├── postcss.config.mjs            ✅ Created
├── .eslintrc.json                ✅ Created
├── .gitignore                    ✅ Created
├── .env.example                  ✅ Created
└── README.md                     # This file
```

## Environment Variables

Create `.env.local` file:

```bash
# Public
NEXT_PUBLIC_SITE_URL=https://sqlmonitor.servicevision.net
NEXT_PUBLIC_CONTACT_EMAIL=info@servicevision.net

# Email (Resend API)
RESEND_API_KEY=re_xxxxxxxxxxxx

# name.com DNS API (for automated DNS updates)
NAMECOM_API_USER=TEDTHERRIAULT
NAMECOM_API_TOKEN=4790fea6e456f7fe9cf4f61a30f025acd63ecd1c
```

## Pages to Create

### 1. Home Page (`app/page.tsx`)

**Hero Section**:
- Headline: "Enterprise SQL Server Monitoring, Self-Hosted"
- Subheadline: "$0-$1,500/year vs. $27k-$37k commercial solutions"
- CTA: "Get Started" + "View Live Demo"
- Animated dashboard preview

**Features Overview**:
- Real-time performance monitoring
- 23 pre-built Grafana dashboards
- Automated alerting
- Zero external dependencies

**Social Proof**:
- "Monitoring 3+ production SQL Servers"
- "615 database objects indexed in 250ms"
- "90-day metrics retention with columnar storage"

**CTA Section**:
- "Start Monitoring in 5 Minutes"
- Link to GitHub
- Link to Docs

### 2. Features Page (`app/features/page.tsx`)

**Core Features**:
- ✅ Real-time DMV collection (<1% CPU overhead)
- ✅ 23 Grafana dashboards (Instance Health, Query Store, Waits, etc.)
- ✅ T-SQL Code Editor with 30+ analysis rules
- ✅ Automated index maintenance recommendations
- ✅ Deadlock monitoring with XML event parsing
- ✅ Blocking chain detection
- ✅ AWS RDS Performance Insights equivalent
- ✅ Query Store integration
- ✅ Wait statistics trending
- ✅ PDF/PNG dashboard export

**Technical Details**:
- Push-based architecture (no OPENQUERY overhead)
- Columnstore index for 10x compression
- Monthly partitioning with automatic cleanup
- SQL Agent jobs (no external agents)
- Docker deployment ready
- Azure, AWS, On-Premise support

### 3. Pricing Page (`app/pricing/page.tsx`)

**Tier 1: Community Edition (Free)**
- $0/month
- Unlimited SQL Server instances
- All features included
- Community support via GitHub
- MIT/Apache 2.0 open source
- Self-hosted deployment

**Tier 2: Enterprise Support**
- $1,500/year
- Everything in Community Edition
- Priority support (email + Teams)
- Custom dashboard development
- Migration assistance
- Training sessions (4 hours/year)
- 99.9% uptime SLA

**Comparison Table**:
| Feature | SQL Monitor | SentryOne | Redgate | SolarWinds |
|---------|-------------|-----------|---------|------------|
| Price (10 servers) | $0-$1,500/year | $27,000/year | $32,000/year | $15,000/year |
| Self-Hosted | ✅ | ✅ | ❌ Cloud only | ✅ |
| Open Source | ✅ | ❌ | ❌ | ❌ |
| Custom Dashboards | ✅ Unlimited | Limited | Limited | Limited |
| Data Retention | 90 days (configurable) | 30 days | 7 days | 30 days |

### 4. Docs Page (`app/docs/page.tsx`)

**Quick Start**:
1. Clone repository
2. Run database setup scripts
3. Deploy Grafana container
4. Configure dashboards
5. Start monitoring

**Deployment Guides**:
- Azure Container Instances
- AWS ECS Fargate
- On-Premise Docker
- SSL/TLS Setup

**Integration Guides**:
- Grafana configuration
- SQL Server linked servers
- Alert notification channels
- Backup & disaster recovery

**API Reference**:
- Link to Swagger/OpenAPI docs
- Authentication endpoints
- Metrics collection API
- Dashboard export API

### 5. Contact Page (`app/contact/page.tsx`)

**Contact Form**:
- Name (required)
- Email (required)
- Company (optional)
- Message (required)
- Submit → sends to info@servicevision.net

**Alternative Contact Methods**:
- Email: info@servicevision.net
- GitHub Issues: https://github.com/dbbuilder/sql-monitor/issues
- Documentation: /docs

## Components to Create

### Navigation (`components/nav.tsx`)

```tsx
- Logo: SQL Monitor
- Links: Home, Features, Pricing, Docs, Contact
- GitHub star button
- Mobile hamburger menu
- Sticky header with backdrop blur
```

### Footer (`components/footer.tsx`)

```tsx
- Company: ServiceVision © 2025
- Links: Features, Pricing, Docs, GitHub, Contact
- Social: GitHub, LinkedIn
- Legal: Privacy Policy, Terms of Service
```

### Contact Form (`components/contact-form.tsx`)

```tsx
- Zod validation
- Real-time error messages
- Success/error toast notifications
- Honeypot field for spam prevention
- reCAPTCHA v3 (optional)
```

## API Routes

### Contact Form (`app/api/contact/route.ts`)

```typescript
import { Resend } from 'resend';
import { z } from 'zod';

const resend = new Resend(process.env.RESEND_API_KEY);

const schema = z.object({
  name: z.string().min(2),
  email: z.string().email(),
  company: z.string().optional(),
  message: z.string().min(10)
});

export async function POST(request: Request) {
  const body = await request.json();
  const validated = schema.parse(body);

  await resend.emails.send({
    from: 'SQL Monitor <noreply@sqlmonitor.servicevision.net>',
    to: 'info@servicevision.net',
    subject: `Contact Form: ${validated.name}`,
    html: `
      <h2>New Contact Form Submission</h2>
      <p><strong>Name:</strong> ${validated.name}</p>
      <p><strong>Email:</strong> ${validated.email}</p>
      <p><strong>Company:</strong> ${validated.company || 'Not provided'}</p>
      <p><strong>Message:</strong></p>
      <p>${validated.message}</p>
    `
  });

  return Response.json({ success: true });
}
```

## DNS Automation

### Update DNS Script (`scripts/update-dns.ts`)

```bash
# Update DNS to point to Vercel
npm run update-dns -- vercel cname.vercel-dns.com

# Update DNS to point to Azure Application Gateway
npm run update-dns -- azure 52.x.x.x

# Update DNS to point to AWS ALB
npm run update-dns -- aws alb-xxxxx.us-east-1.elb.amazonaws.com
```

## Deployment

### Vercel (Recommended)

```bash
# Install Vercel CLI
npm i -g vercel

# Login
vercel login

# Deploy to production
vercel --prod

# Configure custom domain in Vercel dashboard
# Add: sqlmonitor.servicevision.net
```

### Environment Variables in Vercel

Add these in Vercel dashboard → Settings → Environment Variables:

```
RESEND_API_KEY=re_xxxxxxxxxxxx
NAMECOM_API_USER=TEDTHERRIAULT
NAMECOM_API_TOKEN=4790fea6e456f7fe9cf4f61a30f025acd63ecd1c
NEXT_PUBLIC_SITE_URL=https://sqlmonitor.servicevision.net
NEXT_PUBLIC_CONTACT_EMAIL=info@servicevision.net
```

### Update name.com DNS

After deploying to Vercel, update DNS:

```bash
curl -u "TEDTHERRIAULT:4790fea6e456f7fe9cf4f61a30f025acd63ecd1c" \
  -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "host": "sqlmonitor",
    "type": "CNAME",
    "answer": "cname.vercel-dns.com",
    "ttl": 300
  }' \
  https://api.name.com/v4/domains/servicevision.net/records
```

## SEO Optimization

### Metadata (Already Configured)

```tsx
// app/layout.tsx
- title: "SQL Monitor - Self-Hosted SQL Server Monitoring"
- description: "Enterprise-grade SQL Server monitoring..."
- keywords: ["SQL Server", "monitoring", "performance", ...]
- openGraph: Complete OG tags
- twitter: Twitter card metadata
- robots: Proper indexing directives
```

### Additional SEO Tasks

1. **sitemap.xml** (auto-generated by Next.js):
   ```bash
   # Add to app/sitemap.ts
   export default function sitemap() {
     return [
       { url: 'https://sqlmonitor.servicevision.net', changeFrequency: 'weekly' },
       { url: 'https://sqlmonitor.servicevision.net/features', changeFrequency: 'monthly' },
       { url: 'https://sqlmonitor.servicevision.net/pricing', changeFrequency: 'monthly' },
       { url: 'https://sqlmonitor.servicevision.net/docs', changeFrequency: 'weekly' },
     ];
   }
   ```

2. **robots.txt** (auto-generated):
   ```bash
   # Add to app/robots.ts
   export default function robots() {
     return {
       rules: {
         userAgent: '*',
         allow: '/',
       },
       sitemap: 'https://sqlmonitor.servicevision.net/sitemap.xml',
     };
   }
   ```

3. **Analytics** (optional):
   - Google Analytics 4
   - Vercel Analytics (built-in)
   - Plausible Analytics (privacy-focused)

## Performance Optimization

- ✅ Next.js 14 App Router (React Server Components)
- ✅ Tailwind CSS (purges unused styles)
- ✅ Image optimization (next/image)
- ✅ Font optimization (next/font)
- ✅ Static generation where possible
- ✅ Vercel Edge Network CDN

**Target Lighthouse Scores**:
- Performance: 95+
- Accessibility: 100
- Best Practices: 100
- SEO: 100

## Testing

```bash
# Run linter
npm run lint

# Build for production (check for errors)
npm run build

# Run Lighthouse audit
npx lighthouse https://sqlmonitor.servicevision.net --view

# Test contact form
# (Manual testing in browser)
```

## Troubleshooting

### Build Errors

**Error**: "Module not found: Can't resolve '@/components/ui/button'"

**Solution**: Run `npm install` to ensure all dependencies are installed.

### Contact Form Not Sending

**Error**: "Failed to send email"

**Solution**: Verify `RESEND_API_KEY` is set in `.env.local` and Vercel environment variables.

### DNS Not Resolving

**Error**: "DNS_PROBE_FINISHED_NXDOMAIN"

**Solution**:
1. Verify DNS record was created: `dig sqlmonitor.servicevision.net`
2. Wait 5-10 minutes for DNS propagation
3. Check name.com API response for errors

## Next Steps

1. ✅ Install dependencies: `npm install`
2. ✅ Create pages: home, features, pricing, docs, contact
3. ✅ Create components: nav, footer, contact-form
4. ✅ Create API route: /api/contact
5. ✅ Test locally: `npm run dev`
6. ✅ Build: `npm run build`
7. ✅ Deploy to Vercel: `vercel --prod`
8. ✅ Configure custom domain
9. ✅ Update DNS
10. ✅ Test production deployment

## Resources

- **Next.js 14 Docs**: https://nextjs.org/docs
- **Tailwind CSS**: https://tailwindcss.com/docs
- **shadcn/ui**: https://ui.shadcn.com
- **Resend API**: https://resend.com/docs
- **name.com API**: https://www.name.com/api-docs
- **Vercel Deployment**: https://vercel.com/docs

## Support

- **Email**: info@servicevision.net
- **GitHub**: https://github.com/dbbuilder/sql-monitor
- **Main Project**: `/mnt/d/Dev2/sql-monitor`
