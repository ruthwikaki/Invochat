
export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export interface Database {
  public: {
    Tables: {
      alert_history: {
        Row: {
          alert_id: string
          company_id: string
          dismissed_at: string | null
          read_at: string | null
          status: string
        }
        Insert: {
          alert_id: string
          company_id: string
          dismissed_at?: string | null
          read_at?: string | null
          status: string
        }
        Update: {
          alert_id?: string
          company_id?: string
          dismissed_at?: string | null
          read_at?: string | null
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "alert_history_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          }
        ]
      }
      audit_log: {
        Row: {
          action: string
          company_id: string
          created_at: string
          details: Json | null
          id: string
          user_id: string | null
        }
        Insert: {
          action: string
          company_id: string
          created_at?: string
          details?: Json | null
          id?: string
          user_id?: string | null
        }
        Update: {
          action?: string
          company_id?: string
          created_at?: string
          details?: Json | null
          id?: string
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "audit_log_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "audit_log_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          }
        ]
      }
      channel_fees: {
        Row: {
          channel_name: string
          company_id: string
          created_at: string
          fixed_fee: number | null
          id: string
          percentage_fee: number | null
          updated_at: string | null
        }
        Insert: {
          channel_name: string
          company_id: string
          created_at?: string
          fixed_fee?: number | null
          id?: string
          percentage_fee?: number | null
          updated_at?: string | null
        }
        Update: {
          channel_name?: string
          company_id?: string
          created_at?: string
          fixed_fee?: number | null
          id?: string
          percentage_fee?: number | null
          updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "channel_fees_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          }
        ]
      }
      companies: {
        Row: {
          created_at: string
          id: string
          name: string
          owner_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          name: string
          owner_id: string
        }
        Update: {
          created_at?: string
          id?: string
          name?: string
          owner_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "companies_owner_id_fkey"
            columns: ["owner_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          }
        ]
      }
      company_settings: {
        Row: {
          alert_settings: Json | null
          company_id: string
          created_at: string
          currency: string
          dead_stock_days: number
          fast_moving_days: number
          high_value_threshold: number
          overstock_multiplier: number
          predictive_stock_days: number
          tax_rate: number
          timezone: string
          updated_at: string | null
        }
        Insert: {
          alert_settings?: Json | null
          company_id: string
          created_at?: string
          currency?: string
          dead_stock_days?: number
          fast_moving_days?: number
          high_value_threshold?: number
          overstock_multiplier?: number
          predictive_stock_days?: number
          tax_rate?: number
          timezone?: string
          updated_at?: string | null
        }
        Update: {
          alert_settings?: Json | null
          company_id?: string
          created_at?: string
          currency?: string
          dead_stock_days?: number
          fast_moving_days?: number
          high_value_threshold?: number
          overstock_multiplier?: number
          predictive_stock_days?: number
          tax_rate?: number
          timezone?: string
          updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "company_settings_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: true
            referencedRelation: "companies"
            referencedColumns: ["id"]
          }
        ]
      }
      company_users: {
        Row: {
          company_id: string
          role: Database["public"]["Enums"]["company_role"]
          user_id: string
        }
        Insert: {
          company_id: string
          role?: Database["public"]["Enums"]["company_role"]
          user_id: string
        }
        Update: {
          company_id?: string
          role?: Database["public"]["Enums"]["company_role"]
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "company_users_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "company_users_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          }
        ]
      }
      conversations: {
        Row: {
          company_id: string
          created_at: string
          id: string
          is_starred: boolean
          last_accessed_at: string
          title: string
          user_id: string
        }
        Insert: {
          company_id: string
          created_at?: string
          id?: string
          is_starred?: boolean
          last_accessed_at?: string
          title: string
          user_id: string
        }
        Update: {
          company_id?: string
          created_at?: string
          id?: string
          is_starred?: boolean
          last_accessed_at?: string
          title?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "conversations_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "conversations_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          }
        ]
      }
      customers: {
        Row: {
          company_id: string
          created_at: string
          deleted_at: string | null
          email: string | null
          external_customer_id: string | null
          id: string
          name: string | null
          phone: string | null
          updated_at: string | null
        }
        Insert: {
          company_id: string
          created_at?: string
          deleted_at?: string | null
          email?: string | null
          external_customer_id?: string | null
          id?: string
          name?: string | null
          phone?: string | null
          updated_at?: string | null
        }
        Update: {
          company_id?: string
          created_at?: string
          deleted_at?: string | null
          email?: string | null
          external_customer_id?: string | null
          id?: string
          name?: string | null
          phone?: string | null
          updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "customers_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          }
        ]
      }
      export_jobs: {
        Row: {
          completed_at: string | null
          company_id: string
          created_at: string
          download_url: string | null
          error_message: string | null
          expires_at: string | null
          id: string
          requested_by_user_id: string
          status: string
        }
        Insert: {
          completed_at?: string | null
          company_id: string
          created_at?: string
          download_url?: string | null
          error_message?: string | null
          expires_at?: string | null
          id?: string
          requested_by_user_id: string
          status?: string
        }
        Update: {
          completed_at?: string | null
          company_id?: string
          created_at?: string
          download_url?: string | null
          error_message?: string | null
          expires_at?: string | null
          id?: string
          requested_by_user_id?: string
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "export_jobs_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "export_jobs_requested_by_user_id_fkey"
            columns: ["requested_by_user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          }
        ]
      }
      feedback: {
        Row: {
          company_id: string
          created_at: string
          feedback: Database["public"]["Enums"]["feedback_type"]
          id: string
          subject_id: string
          subject_type: string
          user_id: string
        }
        Insert: {
          company_id: string
          created_at?: string
          feedback: Database["public"]["Enums"]["feedback_type"]
          id?: string
          subject_id: string
          subject_type: string
          user_id: string
        }
        Update: {
          company_id?: string
          created_at?: string
          feedback?: Database["public"]["Enums"]["feedback_type"]
          id?: string
          subject_id?: string
          subject_type?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "feedback_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "feedback_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          }
        ]
      }
      imports: {
        Row: {
          completed_at: string | null
          company_id: string
          created_at: string
          created_by: string
          error_count: number | null
          errors: Json | null
          file_name: string
          id: string
          import_type: string
          processed_rows: number | null
          status: string
          summary: Json | null
          total_rows: number | null
        }
        Insert: {
          completed_at?: string | null
          company_id: string
          created_at?: string
          created_by: string
          error_count?: number | null
          errors?: Json | null
          file_name: string
          id?: string
          import_type: string
          processed_rows?: number | null
          status?: string
          summary?: Json | null
          total_rows?: number | null
        }
        Update: {
          completed_at?: string | null
          company_id?: string
          created_at?: string
          created_by?: string
          error_count?: number | null
          errors?: Json | null
          file_name?: string
          id?: string
          import_type?: string
          processed_rows?: number | null
          status?: string
          summary?: Json | null
          total_rows?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "imports_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "imports_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          }
        ]
      }
      integrations: {
        Row: {
          company_id: string
          created_at: string
          id: string
          is_active: boolean
          last_sync_at: string | null
          platform: Database["public"]["Enums"]["integration_platform"]
          shop_domain: string | null
          shop_name: string | null
          sync_status: string | null
          updated_at: string | null
        }
        Insert: {
          company_id: string
          created_at?: string
          id?: string
          is_active?: boolean
          last_sync_at?: string | null
          platform: Database["public"]["Enums"]["integration_platform"]
          shop_domain?: string | null
          shop_name?: string | null
          sync_status?: string | null
          updated_at?: string | null
        }
        Update: {
          company_id?: string
          created_at?: string
          id?: string
          is_active?: boolean
          last_sync_at?: string | null
          platform?: Database["public"]["Enums"]["integration_platform"]
          shop_domain?: string | null
          shop_name?: string | null
          sync_status?: string | null
          updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "integrations_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          }
        ]
      }
      inventory_ledger: {
        Row: {
          change_type: string
          company_id: string
          created_at: string
          id: string
          new_quantity: number
          notes: string | null
          quantity_change: number
          related_id: string | null
          variant_id: string
        }
        Insert: {
          change_type: string
          company_id: string
          created_at?: string
          id?: string
          new_quantity: number
          notes?: string | null
          quantity_change: number
          related_id?: string | null
          variant_id: string
        }
        Update: {
          change_type?: string
          company_id?: string
          created_at?: string
          id?: string
          new_quantity?: number
          notes?: string | null
          quantity_change?: number
          related_id?: string | null
          variant_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "inventory_ledger_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_ledger_variant_id_fkey"
            columns: ["variant_id"]
            isOneToOne: false
            referencedRelation: "product_variants"
            referencedColumns: ["id"]
          }
        ]
      }
      messages: {
        Row: {
          assumptions: string[] | null
          company_id: string
          component: string | null
          component_props: Json | null
          confidence: number | null
          content: string
          conversation_id: string
          created_at: string
          id: string
          is_error: boolean | null
          role: Database["public"]["Enums"]["message_role"]
          visualization: Json | null
        }
        Insert: {
          assumptions?: string[] | null
          company_id: string
          component?: string | null
          component_props?: Json | null
          confidence?: number | null
          content: string
          conversation_id: string
          created_at?: string
          id?: string
          is_error?: boolean | null
          role: Database["public"]["Enums"]["message_role"]
          visualization?: Json | null
        }
        Update: {
          assumptions?: string[] | null
          company_id?: string
          component?: string | null
          component_props?: Json | null
          confidence?: number | null
          content?: string
          conversation_id?: string
          created_at?: string
          id?: string
          is_error?: boolean | null
          role?: Database["public"]["Enums"]["message_role"]
          visualization?: Json | null
        }
        Relationships: [
          {
            foreignKeyName: "messages_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "messages_conversation_id_fkey"
            columns: ["conversation_id"]
            isOneToOne: false
            referencedRelation: "conversations"
            referencedColumns: ["id"]
          }
        ]
      }
      order_line_items: {
        Row: {
          company_id: string
          cost_at_time: number | null
          external_line_item_id: string | null
          fulfillment_status: string | null
          id: string
          order_id: string
          price: number
          product_name: string | null
          quantity: number
          sku: string | null
          tax_amount: number | null
          total_discount: number | null
          variant_id: string | null
          variant_title: string | null
        }
        Insert: {
          company_id: string
          cost_at_time?: number | null
          external_line_item_id?: string | null
          fulfillment_status?: string | null
          id?: string
          order_id: string
          price: number
          product_name?: string | null
          quantity: number
          sku?: string | null
          tax_amount?: number | null
          total_discount?: number | null
          variant_id?: string | null
          variant_title?: string | null
        }
        Update: {
          company_id?: string
          cost_at_time?: number | null
          external_line_item_id?: string | null
          fulfillment_status?: string | null
          id?: string
          order_id?: string
          price?: number
          product_name?: string | null
          quantity?: number
          sku?: string | null
          tax_amount?: number | null
          total_discount?: number | null
          variant_id?: string | null
          variant_title?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "order_line_items_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "order_line_items_order_id_fkey"
            columns: ["order_id"]
            isOneToOne: false
            referencedRelation: "orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "order_line_items_variant_id_fkey"
            columns: ["variant_id"]
            isOneToOne: false
            referencedRelation: "product_variants"
            referencedColumns: ["id"]
          }
        ]
      }
      orders: {
        Row: {
          company_id: string
          created_at: string
          currency: string | null
          customer_id: string | null
          external_order_id: string | null
          financial_status: string | null
          fulfillment_status: string | null
          id: string
          order_number: string
          source_platform: string | null
          subtotal: number
          total_amount: number
          total_discounts: number | null
          total_shipping: number | null
          total_tax: number | null
          updated_at: string | null
        }
        Insert: {
          company_id: string
          created_at?: string
          currency?: string | null
          customer_id?: string | null
          external_order_id?: string | null
          financial_status?: string | null
          fulfillment_status?: string | null
          id?: string
          order_number: string
          source_platform?: string | null
          subtotal: number
          total_amount: number
          total_discounts?: number | null
          total_shipping?: number | null
          total_tax?: number | null
          updated_at?: string | null
        }
        Update: {
          company_id?: string
          created_at?: string
          currency?: string | null
          customer_id?: string | null
          external_order_id?: string | null
          financial_status?: string | null
          fulfillment_status?: string | null
          id?: string
          order_number?: string
          source_platform?: string | null
          subtotal?: number
          total_amount?: number
          total_discounts?: number | null
          total_shipping?: number | null
          total_tax?: number | null
          updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "orders_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "orders_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id"]
          }
        ]
      }
      product_variants: {
        Row: {
          barcode: string | null
          company_id: string
          compare_at_price: number | null
          cost: number | null
          created_at: string
          deleted_at: string | null
          external_variant_id: string | null
          id: string
          in_transit_quantity: number
          inventory_quantity: number
          lead_time_days: number | null
          location: string | null
          option1_name: string | null
          option1_value: string | null
          option2_name: string | null
          option2_value: string | null
          option3_name: string | null
          option3_value: string | null
          price: number | null
          product_id: string
          reorder_point: number | null
          reorder_quantity: number | null
          reserved_quantity: number
          sku: string
          supplier_id: string | null
          title: string | null
          updated_at: string | null
          version: number
        }
        Insert: {
          barcode?: string | null
          company_id: string
          compare_at_price?: number | null
          cost?: number | null
          created_at?: string
          deleted_at?: string | null
          external_variant_id?: string | null
          id?: string
          in_transit_quantity?: number
          inventory_quantity?: number
          lead_time_days?: number | null
          location?: string | null
          option1_name?: string | null
          option1_value?: string | null
          option2_name?: string | null
          option2_value?: string | null
          option3_name?: string | null
          option3_value?: string | null
          price?: number | null
          product_id: string
          reorder_point?: number | null
          reorder_quantity?: number | null
          reserved_quantity?: number
          sku: string
          supplier_id?: string | null
          title?: string | null
          updated_at?: string | null
          version?: number
        }
        Update: {
          barcode?: string | null
          company_id?: string
          compare_at_price?: number | null
          cost?: number | null
          created_at?: string
          deleted_at?: string | null
          external_variant_id?: string | null
          id?: string
          in_transit_quantity?: number
          inventory_quantity?: number
          lead_time_days?: number | null
          location?: string | null
          option1_name?: string | null
          option1_value?: string | null
          option2_name?: string | null
          option2_value?: string | null
          option3_name?: string | null
          option3_value?: string | null
          price?: number | null
          product_id?: string
          reorder_point?: number | null
          reorder_quantity?: number | null
          reserved_quantity?: number
          sku?: string
          supplier_id?: string | null
          title?: string | null
          updated_at?: string | null
          version?: number
        }
        Relationships: [
          {
            foreignKeyName: "product_variants_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "product_variants_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "product_variants_supplier_id_fkey"
            columns: ["supplier_id"]
            isOneToOne: false
            referencedRelation: "suppliers"
            referencedColumns: ["id"]
          }
        ]
      }
      products: {
        Row: {
          company_id: string
          created_at: string
          deleted_at: string | null
          description: string | null
          external_product_id: string | null
          handle: string | null
          id: string
          image_url: string | null
          product_type: string | null
          status: string | null
          tags: string[] | null
          title: string
          updated_at: string | null
          version: number
        }
        Insert: {
          company_id: string
          created_at?: string
          deleted_at?: string | null
          description?: string | null
          external_product_id?: string | null
          handle?: string | null
          id?: string
          image_url?: string | null
          product_type?: string | null
          status?: string | null
          tags?: string[] | null
          title: string
          updated_at?: string | null
          version?: number
        }
        Update: {
          company_id?: string
          created_at?: string
          deleted_at?: string | null
          description?: string | null
          external_product_id?: string | null
          handle?: string | null
          id?: string
          image_url?: string | null
          product_type?: string | null
          status?: string | null
          tags?: string[] | null
          title?: string
          updated_at?: string | null
          version?: number
        }
        Relationships: [
          {
            foreignKeyName: "products_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          }
        ]
      }
      purchase_order_line_items: {
        Row: {
          company_id: string
          cost: number
          id: string
          purchase_order_id: string
          quantity: number
          variant_id: string
        }
        Insert: {
          company_id: string
          cost: number
          id?: string
          purchase_order_id: string
          quantity: number
          variant_id: string
        }
        Update: {
          company_id?: string
          cost?: number
          id?: string
          purchase_order_id?: string
          quantity?: number
          variant_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "purchase_order_line_items_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "purchase_order_line_items_purchase_order_id_fkey"
            columns: ["purchase_order_id"]
            isOneToOne: false
            referencedRelation: "purchase_orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "purchase_order_line_items_variant_id_fkey"
            columns: ["variant_id"]
            isOneToOne: false
            referencedRelation: "product_variants"
            referencedColumns: ["id"]
          }
        ]
      }
      purchase_orders: {
        Row: {
          company_id: string
          created_at: string
          expected_arrival_date: string | null
          id: string
          idempotency_key: string | null
          notes: string | null
          po_number: string
          status: string
          supplier_id: string | null
          total_cost: number
          updated_at: string | null
        }
        Insert: {
          company_id: string
          created_at?: string
          expected_arrival_date?: string | null
          id?: string
          idempotency_key?: string | null
          notes?: string | null
          po_number: string
          status?: string
          supplier_id?: string | null
          total_cost: number
          updated_at?: string | null
        }
        Update: {
          company_id?: string
          created_at?: string
          expected_arrival_date?: string | null
          id?: string
          idempotency_key?: string | null
          notes?: string | null
          po_number?: string
          status?: string
          supplier_id?: string | null
          total_cost?: number
          updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "purchase_orders_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "purchase_orders_supplier_id_fkey"
            columns: ["supplier_id"]
            isOneToOne: false
            referencedRelation: "suppliers"
            referencedColumns: ["id"]
          }
        ]
      }
      refunds: {
        Row: {
          company_id: string
          created_at: string
          created_by_user_id: string | null
          external_refund_id: string | null
          id: string
          note: string | null
          order_id: string
          reason: string | null
          refund_number: string
          status: string
          total_amount: number
        }
        Insert: {
          company_id: string
          created_at?: string
          created_by_user_id?: string | null
          external_refund_id?: string | null
          id?: string
          note?: string | null
          order_id: string
          reason?: string | null
          refund_number: string
          status: string
          total_amount: number
        }
        Update: {
          company_id?: string
          created_at?: string
          created_by_user_id?: string | null
          external_refund_id?: string | null
          id?: string
          note?: string | null
          order_id?: string
          reason?: string | null
          refund_number?: string
          status?: string
          total_amount?: number
        }
        Relationships: [
          {
            foreignKeyName: "refunds_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "refunds_created_by_user_id_fkey"
            columns: ["created_by_user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "refunds_order_id_fkey"
            columns: ["order_id"]
            isOneToOne: false
            referencedRelation: "orders"
            referencedColumns: ["id"]
          }
        ]
      }
      suppliers: {
        Row: {
          company_id: string
          created_at: string
          default_lead_time_days: number | null
          email: string | null
          id: string
          name: string
          notes: string | null
          phone: string | null
          updated_at: string | null
        }
        Insert: {
          company_id: string
          created_at?: string
          default_lead_time_days?: number | null
          email?: string | null
          id?: string
          name: string
          notes?: string | null
          phone?: string | null
          updated_at?: string | null
        }
        Update: {
          company_id?: string
          created_at?: string
          default_lead_time_days?: number | null
          email?: string | null
          id?: string
          name?: string
          notes?: string | null
          phone?: string | null
          updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "suppliers_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          }
        ]
      }
      webhook_events: {
        Row: {
          created_at: string
          id: string
          integration_id: string
          webhook_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          integration_id: string
          webhook_id: string
        }
        Update: {
          created_at?: string
          id?: string
          integration_id?: string
          webhook_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "webhook_events_integration_id_fkey"
            columns: ["integration_id"]
            isOneToOne: false
            referencedRelation: "integrations"
            referencedColumns: ["id"]
          }
        ]
      }
    }
    Views: {
      audit_log_view: {
        Row: {
          action: string | null
          company_id: string | null
          created_at: string | null
          details: Json | null
          id: string | null
          user_email: string | null
        }
        Relationships: [
          {
            foreignKeyName: "audit_log_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          }
        ]
      }
      customers_view: {
        Row: {
          company_id: string | null
          created_at: string | null
          customer_name: string | null
          email: string | null
          first_order_date: string | null
          id: string | null
          total_orders: number | null
          total_spent: number | null
        }
        Relationships: [
          {
            foreignKeyName: "customers_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          }
        ]
      }
      feedback_view: {
        Row: {
          assistant_message_content: string | null
          company_id: string | null
          created_at: string | null
          feedback: Database["public"]["Enums"]["feedback_type"] | null
          id: string | null
          user_email: string | null
          user_message_content: string | null
        }
        Relationships: [
          {
            foreignKeyName: "feedback_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          }
        ]
      }
      orders_view: {
        Row: {
          company_id: string | null
          created_at: string | null
          currency: string | null
          customer_email: string | null
          customer_id: string | null
          external_order_id: string | null
          financial_status: string | null
          fulfillment_status: string | null
          id: string | null
          order_number: string | null
          source_platform: string | null
          subtotal: number | null
          total_amount: number | null
          total_discounts: number | null
          total_shipping: number | null
          total_tax: number | null
          updated_at: string | null
        }
        Relationships: [
          {
            foreignKeyName: "orders_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "orders_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id"]
          }
        ]
      }
      product_variants_with_details: {
        Row: {
          barcode: string | null
          company_id: string | null
          compare_at_price: number | null
          cost: number | null
          created_at: string | null
          external_variant_id: string | null
          id: string | null
          image_url: string | null
          inventory_quantity: number | null
          location: string | null
          option1_name: string | null
          option1_value: string | null
          option2_name: string | null
          option2_value: string | null
          option3_name: string | null
          option3_value: string | null
          price: number | null
          product_id: string | null
          product_status: string | null
          product_title: string | null
          product_type: string | null
          reorder_point: number | null
          reorder_quantity: number | null
          sku: string | null
          supplier_id: string | null
          title: string | null
          updated_at: string | null
        }
        Relationships: [
          {
            foreignKeyName: "product_variants_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "product_variants_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "product_variants_supplier_id_fkey"
            columns: ["supplier_id"]
            isOneToOne: false
            referencedRelation: "suppliers"
            referencedColumns: ["id"]
          }
        ]
      }
      purchase_orders_view: {
        Row: {
          company_id: string | null
          created_at: string | null
          expected_arrival_date: string | null
          id: string | null
          line_items: Json | null
          notes: string | null
          po_number: string | null
          status: string | null
          supplier_name: string | null
          total_cost: number | null
        }
        Relationships: [
          {
            foreignKeyName: "purchase_orders_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          }
        ]
      }
    }
    Functions: {
      adjust_inventory_quantity: {
        Args: {
          p_company_id: string
          p_variant_id: string
          p_new_quantity: number
          p_change_reason: string
          p_user_id: string
        }
        Returns: undefined
      }
      check_user_permission: {
        Args: {
          p_user_id: string
          p_required_role: Database["public"]["Enums"]["company_role"]
        }
        Returns: boolean
      }
      create_full_purchase_order: {
        Args: {
          p_company_id: string
          p_user_id: string
          p_supplier_id: string
          p_status: string
          p_notes: string
          p_expected_arrival: string
          p_line_items: Json
        }
        Returns: {
          id: string
          po_number: string
        }[]
      }
      create_purchase_orders_from_suggestions: {
        Args: {
          p_company_id: string
          p_user_id: string
          p_suggestions: Json
        }
        Returns: number
      }
      detect_anomalies: {
        Args: {
          p_company_id: string
        }
        Returns: {
          date: string
          anomaly_type: string
          daily_revenue: number
          avg_revenue: number
          deviation_percentage: number
        }[]
      }
      forecast_demand: {
        Args: {
          p_company_id: string
        }
        Returns: Json
      }
      get_abc_analysis: {
        Args: {
          p_company_id: string
        }
        Returns: Json
      }
      get_alerts_with_status: {
        Args: {
          p_company_id: string
        }
        Returns: Json
      }
      get_company_id_for_user: {
        Args: {
          p_user_id: string
        }
        Returns: string
      }
      get_customer_analytics: {
        Args: {
          p_company_id: string
        }
        Returns: Json
      }
      get_customer_segment_analysis: {
        Args: {
          p_company_id: string
        }
        Returns: {
          segment: string
          sku: string
          product_name: string
          total_revenue: number
          total_quantity: number
          customer_count: number
        }[]
      }
      get_dashboard_metrics: {
        Args: {
          p_company_id: string
          p_days: number
        }
        Returns: Json
      }
      get_dead_stock_report: {
        Args: {
          p_company_id: string
        }
        Returns: Json
      }
      get_financial_impact_of_promotion: {
        Args: {
          p_company_id: string
          p_skus: string[]
          p_discount_percentage: number
          p_duration_days: number
        }
        Returns: Json
      }
      get_gross_margin_analysis: {
        Args: {
          p_company_id: string
        }
        Returns: Json
      }
      get_historical_sales_for_sku: {
        Args: {
          p_company_id: string
          p_sku: string
        }
        Returns: {
          sale_date: string
          total_quantity: number
        }[]
      }
      get_historical_sales_for_skus: {
        Args: {
          p_company_id: string
          p_skus: string[]
        }
        Returns: Json
      }
      get_inventory_aging_report: {
        Args: {
          p_company_id: string
        }
        Returns: {
          sku: string
          product_name: string
          quantity: number
          total_value: number
          days_since_last_sale: number
        }[]
      }
      get_inventory_analytics: {
        Args: {
          p_company_id: string
        }
        Returns: Json
      }
      get_inventory_turnover: {
        Args: {
          p_company_id: string
          p_days: number
        }
        Returns: Json
      }
      get_margin_trends: {
        Args: {
          p_company_id: string
        }
        Returns: Json
      }
      get_net_margin_by_channel: {
        Args: {
          p_company_id: string
          p_channel_name: string
        }
        Returns: Json
      }
      get_reorder_suggestions: {
        Args: {
          p_company_id: string
        }
        Returns: Json
      }
      get_sales_velocity: {
        Args: {
          p_company_id: string
          p_days: number
          p_limit: number
        }
        Returns: Json
      }
      get_supplier_performance_report: {
        Args: {
          p_company_id: string
        }
        Returns: Json
      }
      get_users_for_company: {
        Args: {
          p_company_id: string
        }
        Returns: {
          id: string
          email: string
          role: Database["public"]["Enums"]["company_role"]
        }[]
      }
      handle_new_user: {
        Args: Record<PropertyKey, never>
        Returns: {
          id: string
          aud: string
          role: string
          email: string
          phone: string
          app_metadata: Json
          user_metadata: Json
          created_at: string
          updated_at: string
          identities: Json
          last_sign_in_at: string
        }
      }
      record_order_from_platform: {
        Args: {
          p_company_id: string
          p_order_payload: Json
          p_platform: string
        }
        Returns: string
      }
      reconcile_inventory_from_integration: {
        Args: {
          p_company_id: string
          p_integration_id: string
          p_user_id: string
        }
        Returns: undefined
      }
      refresh_all_matviews: {
        Args: {
          p_company_id: string
        }
        Returns: undefined
      }
      remove_user_from_company: {
        Args: {
          p_user_id: string
          p_company_id: string
        }
        Returns: undefined
      }
      update_full_purchase_order: {
        Args: {
          p_po_id: string
          p_company_id: string
          p_user_id: string
          p_supplier_id: string
          p_status: string
          p_notes: string
          p_expected_arrival: string
          p_line_items: Json
        }
        Returns: undefined
      }
      update_user_role_in_company: {
        Args: {
          p_user_id: string
          p_company_id: string
          p_new_role: Database["public"]["Enums"]["company_role"]
        }
        Returns: undefined
      }
    }
    Enums: {
      company_role: "Owner" | "Admin" | "Member"
      feedback_type: "helpful" | "unhelpful"
      integration_platform: "shopify" | "woocommerce" | "amazon_fba"
      message_role: "user" | "assistant" | "system" | "tool"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

export type Tables<
  PublicTableNameOrOptions extends
    | keyof (Database["public"]["Tables"] & Database["public"]["Views"])
    | { schema: keyof Database },
  TableName extends PublicTableNameOrOptions extends { schema: keyof Database }
    ? keyof (Database[PublicTableNameOrOptions["schema"]]["Tables"] &
        Database[PublicTableNameOrOptions["schema"]]["Views"])
    : never = never
> = PublicTableNameOrOptions extends { schema: keyof Database }
  ? (Database[PublicTableNameOrOptions["schema"]]["Tables"] &
      Database[PublicTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : PublicTableNameOrOptions extends keyof (Database["public"]["Tables"] &
      Database["public"]["Views"])
  ? (Database["public"]["Tables"] &
      Database["public"]["Views"])[PublicTableNameOrOptions] extends {
      Row: infer R
    }
    ? R
    : never
  : never

export type TablesInsert<
  PublicTableNameOrOptions extends
    | keyof Database["public"]["Tables"]
    | { schema: keyof Database },
  TableName extends PublicTableNameOrOptions extends { schema: keyof Database }
    ? keyof Database[PublicTableNameOrOptions["schema"]]["Tables"]
    : never = never
> = PublicTableNameOrOptions extends { schema: keyof Database }
  ? Database[PublicTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : PublicTableNameOrOptions extends keyof Database["public"]["Tables"]
  ? Database["public"]["Tables"][PublicTableNameOrOptions] extends {
      Insert: infer I
    }
    ? I
    : never
  : never

export type TablesUpdate<
  PublicTableNameOrOptions extends
    | keyof Database["public"]["Tables"]
    | { schema: keyof Database },
  TableName extends PublicTableNameOrOptions extends { schema: keyof Database }
    ? keyof Database[PublicTableNameOrOptions["schema"]]["Tables"]
    : never = never
> = PublicTableNameOrOptions extends { schema: keyof Database }
  ? Database[PublicTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : PublicTableNameOrOptions extends keyof Database["public"]["Tables"]
  ? Database["public"]["Tables"][PublicTableNameOrOptions] extends {
      Update: infer U
    }
    ? U
    : never
  : never

export type Enums<
  PublicEnumNameOrOptions extends
    | keyof Database["public"]["Enums"]
    | { schema: keyof Database },
  EnumName extends PublicEnumNameOrOptions extends { schema: keyof Database }
    ? keyof Database[PublicEnumNameOrOptions["schema"]]["Enums"]
    : never = never
> = PublicEnumNameOrOptions extends { schema: keyof Database }
  ? Database[PublicEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : PublicEnumNameOrOptions extends keyof Database["public"]["Enums"]
  ? Database["public"]["Enums"][PublicEnumNameOrOptions]
  : never


