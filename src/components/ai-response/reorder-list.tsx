import { Card, CardContent } from '@/components/ui/card';

type ReorderListProps = {
  items: string[];
};

export function ReorderList({ items }: ReorderListProps) {
  if (!items || items.length === 0) {
    return <p>No reorder suggestions available.</p>;
  }

  return (
    <Card>
      <CardContent className="p-4">
        <ul className="list-disc space-y-1 pl-5">
          {items.map((item, index) => (
            <li key={index}>{item}</li>
          ))}
        </ul>
      </CardContent>
    </Card>
  );
}
