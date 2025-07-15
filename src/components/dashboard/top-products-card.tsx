'use client';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Avatar, AvatarFallback, AvatarImage } from '@/components/ui/avatar';
import { formatCentsAsCurrency } from '@/lib/utils';
import { TrendingUp, Package } from 'lucide-react';
import { motion } from 'framer-motion';

interface TopProductsCardProps {
  data: {
    product_name: string;
    total_revenue: number;
    image_url: string | null;
  }[];
}

export function TopProductsCard({ data }: TopProductsCardProps) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>Top Selling Products</CardTitle>
        <CardDescription>
          Your best-performing products by revenue.
        </CardDescription>
      </CardHeader>
      <CardContent>
        {data.length > 0 ? (
          <ul className="space-y-4">
            {data.map((product, index) => (
              <motion.li 
                key={index} 
                className="flex items-center gap-4"
                initial={{ opacity: 0, x: -10 }}
                animate={{ opacity: 1, x: 0 }}
                transition={{ duration: 0.3, delay: index * 0.1 }}
              >
                <Avatar className="h-10 w-10 rounded-md">
                  <AvatarImage src={product.image_url || undefined} alt={product.product_name} />
                  <AvatarFallback className="rounded-md bg-muted text-muted-foreground">
                    <Package className="h-5 w-5" />
                  </AvatarFallback>
                </Avatar>
                <div className="flex-1 truncate">
                  <p className="font-medium">{product.product_name}</p>
                </div>
                <div className="font-semibold font-tabular">{formatCentsAsCurrency(product.total_revenue)}</div>
              </motion.li>
            ))}
          </ul>
        ) : (
          <div className="text-center text-muted-foreground py-10">
            <p>No sales data available for this period.</p>
          </div>
        )}
      </CardContent>
    </Card>
  );
}
