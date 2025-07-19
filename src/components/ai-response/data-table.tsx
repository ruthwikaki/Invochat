

import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table';

type DataTableProps = {
  data: Record<string, unknown>[];
};

function formatValue(row: Record<string, unknown>, header: string): string {
  if (header === '__proto__') {
      return 'N/A';
  }
  const value = Object.prototype.hasOwnProperty.call(row, header) ? row[header] : 'N/A';
  if (value === null || value === undefined) return 'N/A';
  if (typeof value === 'object') return JSON.stringify(value);
  return String(value);
}

export function DataTable({ data }: DataTableProps) {
  if (data.length === 0) {
    return <p>No data available to display.</p>;
  }

  const headers = Object.keys(data[0]);

  return (
    <div className="rounded-lg border max-h-96 overflow-auto">
      <Table>
        <TableHeader>
          <TableRow>
            {headers.map((header) => (
              <TableHead key={header}>{header.replace(/_/g, ' ').replace(/\b\w/g, l => l.toUpperCase())}</TableHead>
            ))}
          </TableRow>
        </TableHeader>
        <TableBody>
          {data.map((row, rowIndex) => (
            <TableRow key={rowIndex}>
              {headers.map((header) => (
                <TableCell key={`${rowIndex}-${header}`}>
                  {formatValue(row, header)}
                </TableCell>
              ))}
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </div>
  );
}
