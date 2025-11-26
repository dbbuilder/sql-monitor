# Marketing Site Deployment Guide

This guide walks you through deploying the SQL Monitor marketing site to Vercel and configuring DNS.

## Prerequisites

- Node.js 18+ installed
- Vercel account (free tier works)
- Resend account for contact form emails (free tier: 100 emails/day)
- name.com account access (for DNS configuration)

## Step 1: Install Dependencies

```bash
cd site
npm install
```

## Step 2: Configure Environment Variables

Create `.env.local` file:

```bash
# Public variables
NEXT_PUBLIC_SITE_URL=https://sqlmonitor.servicevision.net
NEXT_PUBLIC_CONTACT_EMAIL=info@servicevision.net

# Resend API key (get from https://resend.com/api-keys)
RESEND_API_KEY=re_xxxxxxxxxxxxxxxxxxxx

# name.com DNS credentials (for automated DNS updates)
NAMECOM_API_USER=TEDTHERRIAULT
NAMECOM_API_TOKEN=4790fea6e456f7fe9cf4f61a30f025acd63ecd1c
```

## Step 3: Test Locally

```bash
# Run development server
npm run dev

# Visit http://localhost:3000
# Test all pages: Home, Features, Pricing, Docs, Contact
```

### Test Checklist

- [ ] Navigation works on all pages
- [ ] All pages load without errors
- [ ] Contact form displays properly
- [ ] Mobile menu works (resize browser to test)
- [ ] Footer links work

## Step 4: Setup Resend for Contact Form

1. **Sign up at https://resend.com** (free tier includes 100 emails/day)

2. **Verify your domain** (or use `onboarding@resend.dev` for testing):
   - Go to Domains → Add Domain
   - Add `sqlmonitor.servicevision.net`
   - Add DNS records to name.com:
     ```
     TXT  @ "resend-domain-verification=xxxxx"
     TXT  @ "v=spf1 include:sendgrid.net ~all"
     CNAME resend._domainkey resend._domainkey.resend.com
     ```

3. **Get API Key**:
   - Go to API Keys → Create API Key
   - Name: "SQL Monitor Contact Form"
   - Permissions: Sending access
   - Copy the key (starts with `re_`)

4. **Add to `.env.local`**:
   ```
   RESEND_API_KEY=re_your_actual_key_here
   ```

5. **Test contact form locally**:
   ```bash
   npm run dev
   # Visit http://localhost:3000/contact
   # Submit test message
   # Check info@servicevision.net for email
   ```

## Step 5: Build for Production

```bash
# Build the site
npm run build

# Test production build locally
npm start

# Visit http://localhost:3000
```

### Fix Any Build Errors

Common issues:

**Error: Missing environment variables**
```bash
# Make sure .env.local exists with all required variables
cat .env.local
```

**Error: TypeScript errors**
```bash
# Check for type errors
npm run lint
```

## Step 6: Deploy to Vercel

### Option A: Vercel CLI (Recommended)

```bash
# Install Vercel CLI
npm i -g vercel

# Login to Vercel
vercel login

# Deploy to production
vercel --prod

# Follow prompts:
# - Link to existing project? No
# - Project name: sql-monitor-marketing
# - Directory: ./
# - Build settings: (auto-detected)
```

### Option B: GitHub + Vercel Integration

1. Push to GitHub:
   ```bash
   git add .
   git commit -m "Add marketing site"
   git push origin main
   ```

2. Import in Vercel:
   - Visit https://vercel.com/new
   - Import repository
   - Configure project:
     - Framework: Next.js
     - Root Directory: `./site`
     - Build Command: `npm run build`
     - Output Directory: `.next`

## Step 7: Configure Vercel Environment Variables

In Vercel dashboard → Settings → Environment Variables:

```
RESEND_API_KEY=re_xxxxxxxxxxxxxxxxxxxx
NAMECOM_API_USER=TEDTHERRIAULT
NAMECOM_API_TOKEN=4790fea6e456f7fe9cf4f61a30f025acd63ecd1c
NEXT_PUBLIC_SITE_URL=https://sqlmonitor.servicevision.net
NEXT_PUBLIC_CONTACT_EMAIL=info@servicevision.net
```

**Important**: Add these to **Production**, **Preview**, and **Development** environments.

## Step 8: Configure Custom Domain in Vercel

1. **In Vercel Dashboard**:
   - Go to your project → Settings → Domains
   - Add domain: `sqlmonitor.servicevision.net`
   - Vercel will provide a CNAME target (e.g., `cname.vercel-dns.com`)

2. **Get the CNAME value** from Vercel:
   ```
   sqlmonitor.servicevision.net → cname.vercel-dns.com
   ```

## Step 9: Update DNS with name.com

### Option A: Automated Script (Recommended)

```bash
# Make sure you're in the site directory
cd site

# Update DNS to point to Vercel
npm run update-dns vercel cname.vercel-dns.com

# Output:
# ✅ DNS record created successfully!
#    FQDN: sqlmonitor.servicevision.net
#    Type: CNAME
#    Answer: cname.vercel-dns.com
#    TTL: 300s
```

### Option B: Manual via name.com Dashboard

1. Login to https://www.name.com
2. Go to My Domains → servicevision.net → DNS Records
3. Delete any existing `sqlmonitor` record
4. Add new CNAME record:
   ```
   Type: CNAME
   Host: sqlmonitor
   Answer: cname.vercel-dns.com
   TTL: 300 (5 minutes)
   ```

### Option C: Manual via name.com API

```bash
# Get existing records
curl -u "TEDTHERRIAULT:4790fea6e456f7fe9cf4f61a30f025acd63ecd1c" \
  https://api.name.com/v4/domains/servicevision.net/records

# Delete old record (if exists) - replace {id} with actual ID
curl -u "TEDTHERRIAULT:4790fea6e456f7fe9cf4f61a30f025acd63ecd1c" \
  -X DELETE \
  https://api.name.com/v4/domains/servicevision.net/records/{id}

# Create new CNAME record
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

## Step 10: Verify Deployment

### DNS Propagation (5-10 minutes)

```bash
# Check DNS propagation
dig sqlmonitor.servicevision.net

# Should show CNAME → cname.vercel-dns.com

# Test from multiple locations
https://www.whatsmydns.net/#CNAME/sqlmonitor.servicevision.net
```

### Test Production Site

1. **Visit https://sqlmonitor.servicevision.net**
2. **Test all pages**:
   - [ ] Home page loads
   - [ ] Features page loads
   - [ ] Pricing page loads
   - [ ] Docs page loads
   - [ ] Contact page loads
3. **Test contact form**:
   - [ ] Fill out form
   - [ ] Submit
   - [ ] Check info@servicevision.net for email
   - [ ] Verify email formatting is correct

### Run Lighthouse Audit

```bash
# Install Lighthouse CLI
npm i -g lighthouse

# Run audit
lighthouse https://sqlmonitor.servicevision.net --view

# Target scores:
# - Performance: 90+
# - Accessibility: 95+
# - Best Practices: 95+
# - SEO: 95+
```

## Step 11: Verify SEO Configuration

### Check sitemap.xml

Visit: https://sqlmonitor.servicevision.net/sitemap.xml

Should show:
```xml
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url>
    <loc>https://sqlmonitor.servicevision.net</loc>
    <lastmod>2025-11-10</lastmod>
    <changefreq>weekly</changefreq>
    <priority>1</priority>
  </url>
  ...
</urlset>
```

### Check robots.txt

Visit: https://sqlmonitor.servicevision.net/robots.txt

Should show:
```
User-agent: *
Allow: /
Disallow: /api/

Sitemap: https://sqlmonitor.servicevision.net/sitemap.xml
```

### Submit to Search Engines

1. **Google Search Console**:
   - Add property: https://sqlmonitor.servicevision.net
   - Verify ownership via DNS TXT record
   - Submit sitemap: https://sqlmonitor.servicevision.net/sitemap.xml

2. **Bing Webmaster Tools**:
   - Add site: https://sqlmonitor.servicevision.net
   - Verify ownership
   - Submit sitemap

## Troubleshooting

### DNS Not Resolving

**Symptom**: `dig sqlmonitor.servicevision.net` returns NXDOMAIN

**Solution**:
1. Verify record was created in name.com
2. Wait 5-10 minutes for propagation
3. Clear DNS cache: `sudo dscacheutil -flushcache` (Mac) or `ipconfig /flushdns` (Windows)

### Contact Form Not Sending Emails

**Symptom**: Form submits but no email received

**Solution**:
1. Check Vercel logs: `vercel logs`
2. Verify `RESEND_API_KEY` is set in Vercel environment variables
3. Check Resend dashboard for errors: https://resend.com/logs
4. Verify email address in `NEXT_PUBLIC_CONTACT_EMAIL`

### Build Fails in Vercel

**Symptom**: Deployment fails during build step

**Solution**:
1. Check build logs in Vercel dashboard
2. Run `npm run build` locally to reproduce error
3. Fix TypeScript errors: `npm run lint`
4. Ensure all dependencies are in `package.json`

### 404 on Subpages

**Symptom**: Homepage works but /features returns 404

**Solution**:
1. Verify Vercel detected Next.js correctly
2. Check build output includes all pages
3. Force redeploy: `vercel --prod --force`

## Maintenance

### Update Content

1. Edit pages in `app/` directory
2. Commit changes:
   ```bash
   git add .
   git commit -m "Update content"
   git push origin main
   ```
3. Vercel auto-deploys on push (if GitHub integration enabled)
4. Or manual deploy: `vercel --prod`

### Monitor Contact Form Usage

Check Resend dashboard for:
- Email delivery rate
- Monthly email count (free tier: 100/day, 3,000/month)
- Bounce/spam reports

### Update Dependencies

```bash
# Check for outdated packages
npm outdated

# Update Next.js
npm install next@latest react@latest react-dom@latest

# Update all dependencies
npm update

# Test locally
npm run build
npm start

# Deploy
vercel --prod
```

## Cost Breakdown

### Vercel Hosting

- **Hobby (Free)**:
  - 100GB bandwidth/month
  - Unlimited deployments
  - Automatic HTTPS
  - **Cost: $0/month**

- **Pro** (if needed):
  - 1TB bandwidth/month
  - Team collaboration
  - Password protection
  - **Cost: $20/month**

### Resend Email

- **Free Tier**:
  - 100 emails/day
  - 3,000 emails/month
  - **Cost: $0/month**

- **Paid** (if contact form gets heavy use):
  - $10/month for 50,000 emails
  - $20/month for 100,000 emails

### name.com DNS

- **Existing domain**: Already paid
- **DNS changes**: Free
- **Total additional cost: $0**

### Total Marketing Site Cost

**Minimum**: **$0/month** (Vercel Hobby + Resend Free)
**With heavy usage**: **$30/month** (Vercel Pro + Resend Paid)

## Next Steps

1. ✅ Deploy marketing site to Vercel
2. ✅ Configure DNS
3. ✅ Test contact form
4. ✅ Submit sitemap to search engines
5. ⏳ Monitor analytics (Vercel Analytics or Google Analytics)
6. ⏳ A/B test pricing page
7. ⏳ Add blog section (optional)
8. ⏳ Setup email newsletter (optional)

## Support

- **Vercel Issues**: https://vercel.com/support
- **Resend Issues**: https://resend.com/support
- **name.com API**: https://www.name.com/api-docs
- **Next.js Issues**: https://github.com/vercel/next.js/issues

## References

- **Next.js 14 Docs**: https://nextjs.org/docs
- **Vercel Deployment**: https://vercel.com/docs
- **Resend Email API**: https://resend.com/docs
- **name.com API**: https://www.name.com/api-docs
- **Tailwind CSS**: https://tailwindcss.com/docs
- **shadcn/ui**: https://ui.shadcn.com
