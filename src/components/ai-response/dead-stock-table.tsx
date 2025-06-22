import type { AnalyzeDeadStockOutput } from '@/ai/flows/dead-stock-analysis';
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table';

type DeadStockTableProps = {
  data: AnalyzeDeadStockOutput['deadStockItems'];
};

export function DeadStockTable({ data }: DeadStockTableProps) {
  if (!data || data.length === 0) {
    return <p>No dead stock found.</p>;
  }

  return (
    <div className="rounded-lg border">
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>Item</TableHead>
            <TableHead className="text-right">Quantity</TableHead>
            <TableHead>Last Sold</TableHead>
            <TableHead>Reason</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {data.map((item) => (
            <TableRow key={item.item}>
              <TableCell className="font-medium">{item.item}</TableCell>
              <TableCell className="text-right">{item.quantity}</TableCell>
              <TableCell>{item.lastSold}</TableCell>
              <TableCell>{item.reason}</TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </div>
  );
}
