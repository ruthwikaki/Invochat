import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table';
import type { SmartReorderingOutput } from '@/ai/flows/smart-reordering';

type ReorderListProps = {
  items: SmartReorderingOutput['reorderList'];
};

export function ReorderList({ items }: ReorderListProps) {
  if (!items || items.length === 0) {
    return <p>No reorder suggestions available.</p>;
  }

  return (
    <div className="rounded-lg border">
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>Item</TableHead>
            <TableHead>Supplier</TableHead>
            <TableHead className="text-right">Current/Reorder</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {items.map((item, index) => (
            <TableRow key={index}>
              <TableCell className="font-medium">{item.name}</TableCell>
              <TableCell>{item.supplier_name}</TableCell>
              <TableCell className="text-right">
                {item.quantity} / {item.reorder_point}
              </TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </div>
  );
}
