#!/usr/bin/env ts-node

/**
 * DNS Update Script for name.com API
 *
 * Updates DNS records for sqlmonitor.servicevision.net
 *
 * Usage:
 *   ts-node update-dns.ts vercel cname.vercel-dns.com
 *   ts-node update-dns.ts azure 52.x.x.x
 *   ts-node update-dns.ts aws alb-xxxxx.us-east-1.elb.amazonaws.com
 */

const NAMECOM_API_USER = process.env.NAMECOM_API_USER || "TEDTHERRIAULT";
const NAMECOM_API_TOKEN = process.env.NAMECOM_API_TOKEN || "4790fea6e456f7fe9cf4f61a30f025acd63ecd1c";
const DOMAIN = "servicevision.net";
const SUBDOMAIN = "sqlmonitor";

interface DNSRecord {
  id: number;
  domainName: string;
  host: string;
  fqdn: string;
  type: string;
  answer: string;
  ttl: number;
}

interface NamecomListResponse {
  records: DNSRecord[];
}

interface NamecomCreateResponse {
  id: number;
  domainName: string;
  host: string;
  fqdn: string;
  type: string;
  answer: string;
  ttl: number;
}

async function updateDNS(target: "vercel" | "azure" | "aws", address: string): Promise<void> {
  const auth = Buffer.from(`${NAMECOM_API_USER}:${NAMECOM_API_TOKEN}`).toString("base64");
  const headers = {
    "Authorization": `Basic ${auth}`,
    "Content-Type": "application/json",
  };

  console.log(`\n📝 Updating DNS for ${SUBDOMAIN}.${DOMAIN}`);
  console.log(`   Target: ${target}`);
  console.log(`   Address: ${address}\n`);

  try {
    // Step 1: List existing records
    console.log("Step 1: Fetching existing DNS records...");
    const listResponse = await fetch(`https://api.name.com/v4/domains/${DOMAIN}/records`, {
      headers,
    });

    if (!listResponse.ok) {
      throw new Error(`Failed to list records: ${listResponse.statusText}`);
    }

    const listData: NamecomListResponse = await listResponse.json();
    const existingRecord = listData.records.find((r: DNSRecord) => r.host === SUBDOMAIN);

    // Step 2: Delete existing record if found
    if (existingRecord) {
      console.log(`   Found existing ${existingRecord.type} record: ${existingRecord.answer}`);
      console.log(`   Deleting record ID ${existingRecord.id}...`);

      const deleteResponse = await fetch(
        `https://api.name.com/v4/domains/${DOMAIN}/records/${existingRecord.id}`,
        {
          method: "DELETE",
          headers,
        }
      );

      if (!deleteResponse.ok) {
        throw new Error(`Failed to delete record: ${deleteResponse.statusText}`);
      }

      console.log("   ✓ Record deleted\n");
    } else {
      console.log("   No existing record found\n");
    }

    // Step 3: Create new record
    console.log("Step 2: Creating new DNS record...");
    const recordType = target === "vercel" || target === "aws" ? "CNAME" : "A";
    const newRecord = {
      host: SUBDOMAIN,
      type: recordType,
      answer: address,
      ttl: 300,
    };

    console.log(`   Type: ${recordType}`);
    console.log(`   Value: ${address}`);
    console.log(`   TTL: 300 seconds\n`);

    const createResponse = await fetch(`https://api.name.com/v4/domains/${DOMAIN}/records`, {
      method: "POST",
      headers,
      body: JSON.stringify(newRecord),
    });

    if (!createResponse.ok) {
      const errorText = await createResponse.text();
      throw new Error(`Failed to create record: ${createResponse.statusText}\n${errorText}`);
    }

    const createData: NamecomCreateResponse = await createResponse.json();
    console.log("✅ DNS record created successfully!\n");
    console.log(`   FQDN: ${createData.fqdn}`);
    console.log(`   Type: ${createData.type}`);
    console.log(`   Answer: ${createData.answer}`);
    console.log(`   TTL: ${createData.ttl}s\n`);

    console.log("⏱️  DNS propagation may take 5-10 minutes.");
    console.log(`   Test with: dig ${SUBDOMAIN}.${DOMAIN}\n`);
  } catch (error) {
    console.error("\n❌ Error updating DNS:");
    console.error(error instanceof Error ? error.message : String(error));
    process.exit(1);
  }
}

// Main execution
const args = process.argv.slice(2);

if (args.length !== 2) {
  console.error("\n❌ Usage: ts-node update-dns.ts <target> <address>\n");
  console.error("Examples:");
  console.error("  ts-node update-dns.ts vercel cname.vercel-dns.com");
  console.error("  ts-node update-dns.ts azure 52.143.78.123");
  console.error("  ts-node update-dns.ts aws alb-xxxxx.us-east-1.elb.amazonaws.com\n");
  process.exit(1);
}

const [target, address] = args;

if (!["vercel", "azure", "aws"].includes(target)) {
  console.error(`\n❌ Invalid target: ${target}`);
  console.error("   Valid targets: vercel, azure, aws\n");
  process.exit(1);
}

updateDNS(target as "vercel" | "azure" | "aws", address);
