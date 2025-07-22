
import { getServiceRoleClient } from '@/lib/supabase/admin';
import type { Order, Product, Supplier, Customer } from '@/types';

export class DatabaseQueries {
  private supabase = getServiceRoleClient();

  async getCompanyProducts(companyId: string) {
    const { data, error } = await this.supabase
      .from('product_variants_with_details')
      .select('*')
      .eq('company_id', companyId);
    
    if (error) throw error;
    return data || [];
  }

  async getCompanyOrders(companyId: string, limit?: number): Promise<Order[]> {
    let query = this.supabase
      .from('orders_view')
      .select('*')
      .eq('company_id', companyId)
      .order('created_at', { ascending: false });
    
    if (limit) query = query.limit(limit);
    
    const { data, error } = await query;
    if (error) throw error;
    return (data as Order[]) || [];
  }
  
  async getCompanyCustomers(companyId: string, limit?: number): Promise<Customer[]> {
    let query = this.supabase
      .from('customers_view')
      .select('*')
      .eq('company_id', companyId)
      .order('created_at', { ascending: false });
    
    if (limit) query = query.limit(limit);
    
    const { data, error } = await query;
    if (error) throw error;
    return (data as Customer[]) || [];
  }
  
  async getCompanySuppliers(companyId: string): Promise<Supplier[]> {
    const { data, error } = await this.supabase
      .from('suppliers')
      .select('*')
      .eq('company_id', companyId);
      
    if (error) throw error;
    return data || [];
  }
  
  async getDeadStock(companyId: string) {
    const ninetyDaysAgo = new Date(Date.now() - 90 * 24 * 60 * 60 * 1000);
    const { data, error } = await this.supabase
      .from('product_variants_with_details')
      .select('*')
      .eq('company_id', companyId)
      .lt('updated_at', ninetyDaysAgo.toISOString())
      .gt('inventory_quantity', 0);
    if (error) throw error;
    return data || [];
  }

  async getInventoryMetrics(companyId: string) {
    const { data, error } = await this.supabase.rpc('get_inventory_metrics', {
      p_company_id: companyId
    });
    
    if (error) throw error;
    return data;
  }

  async getReorderSuggestions(companyId: string) {
    const { data, error } = await this.supabase.rpc('get_reorder_suggestions', {
      p_company_id: companyId
    });
    
    if (error) throw error;
    return data || [];
  }
}

export const db = new DatabaseQueries();

    