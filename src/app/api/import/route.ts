
import { createServerClient, type CookieOptions } from '@supabase/ssr';
import { cookies } from 'next/headers';
import { type NextRequest, NextResponse } from 'next/server';

export async function POST(request: NextRequest) {
  const cookieStore = cookies();
  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        get(name: string) {
          return cookieStore.get(name)?.value
        },
        set(name: string, value: string, options: CookieOptions) {
          cookieStore.set({ name, value, ...options })
        },
        remove(name: string, options: CookieOptions) {
          cookieStore.set({ name, value: '', ...options })
        },
      },
    }
  );

  try {
    // Get authenticated user
    const { data: { user }, error: authError } = await supabase.auth.getUser();
    if (authError || !user) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
    }
    
    // Get user's company_id from their auth metadata. This is more reliable.
    const companyId = user.app_metadata?.company_id;
    if (!companyId) {
        return NextResponse.json({
            error: 'Could not determine your company. Setup might be incomplete.'
        }, { status: 400 });
    }
    
    // Parse request body
    const { items } = await request.json();
    
    if (!items || !Array.isArray(items) || items.length === 0) {
      return NextResponse.json({ 
        error: 'No items provided for import' 
      }, { status: 400 });
    }
    
    // Prepare items for bulk insertion
    const inventoryItems = items.map((item: any) => ({
      company_id: companyId,
      sku: item.sku || `SKU-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`,
      name: item.name || 'Unnamed Item',
      description: item.description || '',
      category: item.category || 'Uncategorized',
      quantity: parseInt(item.quantity) || 0,
      cost: parseFloat(item.cost) || 0,
      price: parseFloat(item.price) || 0,
      reorder_point: parseInt(item.reorder_point) || 10,
      reorder_qty: parseInt(item.reorder_qty) || 50,
      supplier_name: item.supplier_name || null,
      warehouse_name: item.warehouse_name || 'Main Warehouse',
      last_sold_date: item.last_sold_date || null,
    }));
    
    // Perform bulk insert using the admin client to bypass RLS for this trusted server operation
    const { data, error: insertError } = await supabase
      .from('inventory')
      .insert(inventoryItems)
      .select();
      
    if (insertError) {
      console.error('Import error:', insertError);
      return NextResponse.json({ 
        error: `Import failed: ${insertError.message}` 
      }, { status: 400 });
    }
    
    // Caching is handled by TTL now, so direct invalidation here is removed for simplicity and robustness.
    
    // Return success with count
    return NextResponse.json({ 
      success: true, 
      count: data?.length || 0,
      message: `Successfully imported ${data?.length || 0} items` 
    });
    
  } catch (error: any) {
    console.error('Import API error:', error);
    return NextResponse.json(
      { error: error.message || 'Import failed' }, 
      { status: 500 }
    );
  }
}
