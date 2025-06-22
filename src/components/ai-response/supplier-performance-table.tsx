import type { SupplierPerformanceOutput } from '@/ai/flows/supplier-performance';
import { Progress } from '@/components/ui/progress';
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table';

type SupplierPerformanceTableProps = {
  data: SupplierPerformanceOutput['rankedVendors'];
};

export function SupplierPerformanceTable({
  data,
}: SupplierPerformanceTableProps) {
  if (!data || data.length === 0) {
    return <p>No supplier performance data available.</p>;
  }

  return (
    <div className="rounded-lg border">
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>Vendor</TableHead>
            <TableHead>On-Time Delivery</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {data.map((vendor) => (
            <TableRow key={vendor.vendorName}>
              <TableCell className="font-medium">{vendor.vendorName}</TableCell>
              <TableCell>
                <div className="flex items-center gap-2">
                  <Progress
                    value={vendor.onTimeDeliveryRate}
                    className="w-2/3"
                  />
                  <span>{vendor.onTimeDeliveryRate}%</span>
                </div>
              </TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </div>
  );
}
