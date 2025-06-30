
import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from '@/components/ui/accordion';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { getDatabaseSchemaAndData } from '@/app/data-actions';
import { DataTable } from '@/components/ai-response/data-table';
import { Database } from 'lucide-react';
import { AppPage, AppPageHeader } from '@/components/ui/page';

export default async function DatabaseExplorerPage() {
  const schemaData = await getDatabaseSchemaAndData();

  return (
    <AppPage>
      <AppPageHeader
          title="Database Explorer"
          description="A direct view of the tables in your database and a preview of their data."
      />
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2"><Database className="h-5 w-5" /> Live Database View</CardTitle>
          <CardDescription>
            This helps verify data imports and see exactly what the AI has access to query.
          </CardDescription>
        </CardHeader>
        <CardContent>
          {schemaData.length > 0 ? (
            <Accordion type="single" collapsible className="w-full">
              {schemaData.map(({ tableName, rows }) => (
                <AccordionItem value={tableName} key={tableName}>
                  <AccordionTrigger className="text-lg font-medium capitalize">{tableName.replace(/_/g, ' ')}</AccordionTrigger>
                  <AccordionContent>
                    {rows.length > 0 ? (
                      <DataTable data={rows} />
                    ) : (
                      <p className="text-muted-foreground p-4 text-center">This table is empty for your company or could not be loaded.</p>
                    )}
                  </AccordionContent>
                </AccordionItem>
              ))}
            </Accordion>
          ) : (
             <p className="text-muted-foreground p-4 text-center">Could not load any tables from the database.</p>
          )}
        </CardContent>
      </Card>
    </AppPage>
  );
}
