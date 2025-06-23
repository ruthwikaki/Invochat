import type { SupplierPerformanceOutput } from '@/ai/flows/supplier-performance';
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table';

type SupplierPerformanceTableProps = {
  data: SupplierPerformanceOutput['vendors'];
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
            <TableHead>Contact</TableHead>
            <TableHead>Terms</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {data.map((vendor) => (
            <TableRow key={vendor.vendorName}>
              <TableCell className="font-medium">{vendor.vendorName}</TableCell>
              <TableCell>{vendor.contactInfo}</TableCell>
              <TableCell>{vendor.terms}</TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </div>
  );
}
