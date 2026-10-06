
export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[]

export type Database = {
  
  "graphql_public": {
          Tables: {
            [_ in never]: never
          }
          Views: {
            [_ in never]: never
          }
          Functions: {
            "graphql":
{ Args: { "extensions"?: Json,"operationName"?: string,"query"?: string,"variables"?: Json }; Returns: Json
                           }
          }
          Enums: {
            [_ in never]: never
          }
          CompositeTypes: {
            [_ in never]: never
          }
        },"public": {
          Tables: {
            "budget_settings": {
                  Row: {
                    "created_at": string,"essential_pct": number,"fun_pct": number,"invest_pct": number,"user_id": string
                  }
                  Insert: {
                    "created_at"?: string,"essential_pct"?: number,"fun_pct"?: number,"invest_pct"?: number,"user_id": string
                  }
                  Update: {
                    "created_at"?: string,"essential_pct"?: number,"fun_pct"?: number,"invest_pct"?: number,"user_id"?: string
                  }
                  Relationships: [
                    
                  ]
                },"categories": {
                  Row: {
                    "archived": boolean,"bucket": Database["public"]['Enums']["bucket"],"created_at": string,"id": string,"name": string,"user_id": string
                  }
                  Insert: {
                    "archived"?: boolean,"bucket": Database["public"]['Enums']["bucket"],"created_at"?: string,"id"?: string,"name": string,"user_id": string
                  }
                  Update: {
                    "archived"?: boolean,"bucket"?: Database["public"]['Enums']["bucket"],"created_at"?: string,"id"?: string,"name"?: string,"user_id"?: string
                  }
                  Relationships: [
                    
                  ]
                },"entries": {
                  Row: {
                    "amount_cents": number,"bucket": Database["public"]['Enums']["bucket"] | null,"category_id": string | null,"created_at": string,"fund_flow": string | null,"fund_id": string | null,"id": string,"installment_index": number | null,"month_id": string,"note": string | null,"paid_on": string,"recurring_template_id": string | null,"user_id": string
                  }
                  Insert: {
                    "amount_cents": number,"bucket"?: Database["public"]['Enums']["bucket"] | null,"category_id"?: string | null,"created_at"?: string,"fund_flow"?: string | null,"fund_id"?: string | null,"id"?: string,"installment_index"?: number | null,"month_id": string,"note"?: string | null,"paid_on": string,"recurring_template_id"?: string | null,"user_id": string
                  }
                  Update: {
                    "amount_cents"?: number,"bucket"?: Database["public"]['Enums']["bucket"] | null,"category_id"?: string | null,"created_at"?: string,"fund_flow"?: string | null,"fund_id"?: string | null,"id"?: string,"installment_index"?: number | null,"month_id"?: string,"note"?: string | null,"paid_on"?: string,"recurring_template_id"?: string | null,"user_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "entries_fund_fkey"
      columns: ["user_id","fund_id"]
isOneToOne: false
      referencedRelation: "funds"
      referencedColumns: ["user_id","id"]
    },{
      foreignKeyName: "entries_user_id_category_id_fkey"
      columns: ["user_id","category_id"]
isOneToOne: false
      referencedRelation: "categories"
      referencedColumns: ["user_id","id"]
    },{
      foreignKeyName: "entries_user_id_month_id_fkey"
      columns: ["user_id","month_id"]
isOneToOne: false
      referencedRelation: "months"
      referencedColumns: ["user_id","id"]
    },{
      foreignKeyName: "entries_user_id_recurring_template_id_fkey"
      columns: ["user_id","recurring_template_id"]
isOneToOne: false
      referencedRelation: "recurring_templates"
      referencedColumns: ["user_id","id"]
    }
                  ]
                },"extra_income": {
                  Row: {
                    "amount_cents": number,"created_at": string,"id": string,"month_id": string,"note": string | null,"received_on": string,"user_id": string
                  }
                  Insert: {
                    "amount_cents": number,"created_at"?: string,"id"?: string,"month_id": string,"note"?: string | null,"received_on": string,"user_id": string
                  }
                  Update: {
                    "amount_cents"?: number,"created_at"?: string,"id"?: string,"month_id"?: string,"note"?: string | null,"received_on"?: string,"user_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "extra_income_user_id_month_id_fkey"
      columns: ["user_id","month_id"]
isOneToOne: false
      referencedRelation: "months"
      referencedColumns: ["user_id","id"]
    }
                  ]
                },"funds": {
                  Row: {
                    "achieved_at": string | null,"active": boolean,"created_at": string,"goal_cents": number | null,"id": string,"kind": Database["public"]['Enums']["fund_kind"],"name": string,"user_id": string
                  }
                  Insert: {
                    "achieved_at"?: string | null,"active"?: boolean,"created_at"?: string,"goal_cents"?: number | null,"id"?: string,"kind": Database["public"]['Enums']["fund_kind"],"name": string,"user_id": string
                  }
                  Update: {
                    "achieved_at"?: string | null,"active"?: boolean,"created_at"?: string,"goal_cents"?: number | null,"id"?: string,"kind"?: Database["public"]['Enums']["fund_kind"],"name"?: string,"user_id"?: string
                  }
                  Relationships: [
                    
                  ]
                },"month_summaries": {
                  Row: {
                    "created_at": string,"essential_budget_cents": number,"essential_rest_cents": number,"essential_spent_cents": number,"extra_income_cents": number,"fun_budget_cents": number,"fun_rest_cents": number,"fun_spent_cents": number,"invest_target_cents": number,"invested_cents": number,"month_id": string,"net_income_cents": number,"user_id": string
                  }
                  Insert: {
                    "created_at"?: string,"essential_budget_cents": number,"essential_rest_cents": number,"essential_spent_cents": number,"extra_income_cents"?: number,"fun_budget_cents": number,"fun_rest_cents": number,"fun_spent_cents": number,"invest_target_cents": number,"invested_cents": number,"month_id": string,"net_income_cents": number,"user_id": string
                  }
                  Update: {
                    "created_at"?: string,"essential_budget_cents"?: number,"essential_rest_cents"?: number,"essential_spent_cents"?: number,"extra_income_cents"?: number,"fun_budget_cents"?: number,"fun_rest_cents"?: number,"fun_spent_cents"?: number,"invest_target_cents"?: number,"invested_cents"?: number,"month_id"?: string,"net_income_cents"?: number,"user_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "month_summaries_user_id_month_id_fkey"
      columns: ["user_id","month_id"]
isOneToOne: false
      referencedRelation: "months"
      referencedColumns: ["user_id","id"]
    }
                  ]
                },"months": {
                  Row: {
                    "closed_at": string | null,"created_at": string,"essential_pct": number,"fun_pct": number,"id": string,"invest_pct": number,"invested_cents": number | null,"month": number,"net_income_cents": number,"status": Database["public"]['Enums']["month_status"],"user_id": string,"year": number
                  }
                  Insert: {
                    "closed_at"?: string | null,"created_at"?: string,"essential_pct": number,"fun_pct": number,"id"?: string,"invest_pct": number,"invested_cents"?: number | null,"month": number,"net_income_cents": number,"status"?: Database["public"]['Enums']["month_status"],"user_id": string,"year": number
                  }
                  Update: {
                    "closed_at"?: string | null,"created_at"?: string,"essential_pct"?: number,"fun_pct"?: number,"id"?: string,"invest_pct"?: number,"invested_cents"?: number | null,"month"?: number,"net_income_cents"?: number,"status"?: Database["public"]['Enums']["month_status"],"user_id"?: string,"year"?: number
                  }
                  Relationships: [
                    
                  ]
                },"profiles": {
                  Row: {
                    "created_at": string,"display_name": string | null,"user_id": string
                  }
                  Insert: {
                    "created_at"?: string,"display_name"?: string | null,"user_id": string
                  }
                  Update: {
                    "created_at"?: string,"display_name"?: string | null,"user_id"?: string
                  }
                  Relationships: [
                    
                  ]
                },"recurring_templates": {
                  Row: {
                    "active": boolean,"amount_cents": number,"category_id": string,"created_at": string,"day_of_month": number,"first_month": number | null,"first_year": number | null,"id": string,"installments_total": number | null,"label": string,"user_id": string
                  }
                  Insert: {
                    "active"?: boolean,"amount_cents": number,"category_id": string,"created_at"?: string,"day_of_month": number,"first_month"?: number | null,"first_year"?: number | null,"id"?: string,"installments_total"?: number | null,"label": string,"user_id": string
                  }
                  Update: {
                    "active"?: boolean,"amount_cents"?: number,"category_id"?: string,"created_at"?: string,"day_of_month"?: number,"first_month"?: number | null,"first_year"?: number | null,"id"?: string,"installments_total"?: number | null,"label"?: string,"user_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "recurring_templates_user_id_category_id_fkey"
      columns: ["user_id","category_id"]
isOneToOne: false
      referencedRelation: "categories"
      referencedColumns: ["user_id","id"]
    }
                  ]
                }
          }
          Views: {
            "fund_balances": {
                  Row: {
                    "balance_cents": number | null,"fund_id": string | null
                  }
                  Relationships: [
                    
                  ]
                }
          }
          Functions: {
            "close_month":
{ Args: { "invested_cents": number,"month_id": string }; Returns: {
              "created_at": string,
"essential_budget_cents": number,
"essential_rest_cents": number,
"essential_spent_cents": number,
"extra_income_cents": number,
"fun_budget_cents": number,
"fun_rest_cents": number,
"fun_spent_cents": number,
"invest_target_cents": number,
"invested_cents": number,
"month_id": string,
"net_income_cents": number,
"user_id": string
            }
                          SetofOptions: {
        from: "*"
        to: "month_summaries"
        isOneToOne: true
        isSetofReturn: false
      } },
"create_recurring_template":
{ Args: { "p_amount_cents": number,"p_category_id": string,"p_day_of_month": number,"p_first_month"?: number,"p_first_year"?: number,"p_installments_total"?: number,"p_label": string }; Returns: {
              "active": boolean,
"amount_cents": number,
"category_id": string,
"created_at": string,
"day_of_month": number,
"first_month": number | null,
"first_year": number | null,
"id": string,
"installments_total": number | null,
"label": string,
"user_id": string
            }
                          SetofOptions: {
        from: "*"
        to: "recurring_templates"
        isOneToOne: true
        isSetofReturn: false
      } },
"delete_fund":
{ Args: { "p_fund_id": string,"p_move_to_extras"?: boolean }; Returns: undefined
                           },
"deposit_to_fund":
{ Args: { "p_essential_cents"?: number,"p_fun_cents"?: number,"p_fund_id": string,"p_month_id": string,"p_note"?: string,"p_paid_on"?: string }; Returns: undefined
                           },
"open_month":
{ Args: { "month": number,"net_income_cents": number,"year": number }; Returns: {
              "closed_at": string | null,
"created_at": string,
"essential_pct": number,
"fun_pct": number,
"id": string,
"invest_pct": number,
"invested_cents": number | null,
"month": number,
"net_income_cents": number,
"status": Database["public"]['Enums']["month_status"],
"user_id": string,
"year": number
            }
                          SetofOptions: {
        from: "*"
        to: "months"
        isOneToOne: true
        isSetofReturn: false
      } },
"reopen_month":
{ Args: { "month_id": string }; Returns: {
              "closed_at": string | null,
"created_at": string,
"essential_pct": number,
"fun_pct": number,
"id": string,
"invest_pct": number,
"invested_cents": number | null,
"month": number,
"net_income_cents": number,
"status": Database["public"]['Enums']["month_status"],
"user_id": string,
"year": number
            }
                          SetofOptions: {
        from: "*"
        to: "months"
        isOneToOne: true
        isSetofReturn: false
      } }
          }
          Enums: {
            "bucket": "essential"|"fun","fund_kind": "bank"|"piggy","month_status": "open"|"closed"
          }
          CompositeTypes: {
            [_ in never]: never
          }
        }
}

type DatabaseWithoutInternals = Omit<Database, '__InternalSupabase'>

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
  ? (DefaultSchema["Tables"] & DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
      Row: infer R
    }
    ? R
    : never
  : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
  ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
      Insert: infer I
    }
    ? I
    : never
  : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
  ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
      Update: infer U
    }
    ? U
    : never
  : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never
> = DefaultSchemaEnumNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
  ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
  : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never
> = PublicCompositeTypeNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
  ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
  : never

export const Constants = {
  "graphql_public": {
          Enums: {
            
          }
        },"public": {
          Enums: {
            "bucket": ["essential", "fun"],"fund_kind": ["bank", "piggy"],"month_status": ["open", "closed"]
          }
        }
} as const
