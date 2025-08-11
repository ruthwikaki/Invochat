
import { NextResponse } from "next/server";
import { getAuthContext } from "@/lib/auth-helpers";
import { getUnifiedInventoryFromDB } from "@/services/database";
import Papa from "papaparse";

export async function GET() {
  try {
    const { companyId } = await getAuthContext();
    const { items } = await getUnifiedInventoryFromDB(companyId, { limit: 10000 });

    const dataToExport = items.map(item => ({
        product_title: item.product_title,
        variant_title: item.title,
        sku: item.sku,
        inventory_quantity: item.inventory_quantity,
        price_dollars: item.price ? (item.price / 100).toFixed(2) : '0.00',
        cost_dollars: item.cost ? (item.cost / 100).toFixed(2) : '0.00',
    }));

    const csv = Papa.unparse(dataToExport);

    return new NextResponse(csv, {
      status: 200,
      headers: {
        "Content-Type": "text/csv; charset=utf-8",
        "Content-Disposition": `attachment; filename="inventory-export-${new Date().toISOString().split('T')[0]}.csv"`,
      },
    });
  } catch (e) {
    const error = e instanceof Error ? e.message : "An unknown error occurred.";
    return NextResponse.json({ error: `Export failed: ${error}` }, { status: 500 });
  }
}
