import { NextResponse } from "next/server";
import { runDemoTrade } from "@/lib/demoTrader";

export async function POST() {
  try {
    const result = await runDemoTrade();
    console.log("RESPONSE", result);
    return NextResponse.json({ ok: true, result });
  } catch (err) {
    console.error("[demo-trader] error", err);
    return new NextResponse("demo trader failed", { status: 500 });
  }
}
