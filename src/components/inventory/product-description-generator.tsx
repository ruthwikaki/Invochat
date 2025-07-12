
'use client';

import { useState, useTransition } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter, DialogClose } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Loader2, Sparkles } from 'lucide-react';
import { useToast } from '@/hooks/use-toast';
import type { UnifiedInventoryItem, ProductUpdateData } from '@/types';
import { getGeneratedProductDescription, updateProduct } from '@/app/data-actions';
import { Skeleton } from '../ui/skeleton';

interface ProductDescriptionGeneratorDialogProps {
    item: UnifiedInventoryItem | null;
    onClose: () => void;
    onSaveSuccess: (updatedItem: UnifiedInventoryItem) => void;
}

const formSchema = z.object({
  keywords: z.string().min(3, { message: 'Please provide at least one keyword.' }),
});

type FormData = z.infer<typeof formSchema>;

export function ProductDescriptionGeneratorDialog({ item, onClose, onSaveSuccess }: ProductDescriptionGeneratorDialogProps) {
    const { toast } = useToast();
    const [generatePending, startGenerateTransition] = useTransition();
    const [savePending, startSaveTransition] = useTransition();
    const [generatedContent, setGeneratedContent] = useState<{ suggestedName: string; description: string } | null>(null);

    const form = useForm<FormData>({
        resolver: zodResolver(formSchema),
    });

    const handleGenerate = (data: FormData) => {
        if (!item) return;

        startGenerateTransition(async () => {
            const keywords = data.keywords.split(',').map(k => k.trim());
            const result = await getGeneratedProductDescription(item.product_name, item.category || '', keywords);
            setGeneratedContent(result);
        });
    };

    const handleSaveChanges = () => {
        if (!item || !generatedContent) return;
        
        const updateData: ProductUpdateData = {
            name: generatedContent.suggestedName,
            // You might want to update a 'description' field here if it exists.
            // For now, we'll just log it.
        };

        startSaveTransition(async () => {
            console.log("Saving generated description to product notes or a dedicated field is not yet implemented.");
            const result = await updateProduct(item.product_id, updateData);
            if (result.success && result.updatedItem) {
                toast({ title: 'Product Updated', description: `Product name updated to "${result.updatedItem.product_name}".` });
                onSaveSuccess(result.updatedItem);
                onClose();
            } else {
                toast({ variant: 'destructive', title: 'Error', description: result.error });
            }
        });
    }

    const resetState = () => {
        setGeneratedContent(null);
        form.reset();
        onClose();
    };

    return (
        <Dialog open={!!item} onOpenChange={(open) => !open && resetState()}>
            <DialogContent className="sm:max-w-lg">
                <DialogHeader>
                    <DialogTitle className="flex items-center gap-2">
                        <Sparkles className="h-5 w-5 text-primary" />
                        Generate Product Description
                    </DialogTitle>
                    <DialogDescription>
                        Use AI to create a compelling name and description for: <strong>{item?.product_name}</strong>
                    </DialogDescription>
                </DialogHeader>
                {!generatedContent ? (
                    <form onSubmit={form.handleSubmit(handleGenerate)} className="space-y-4 py-4">
                        <div className="space-y-2">
                            <Label htmlFor="keywords">Keywords</Label>
                            <Input id="keywords" {...form.register('keywords')} placeholder="e.g., durable, lightweight, waterproof" />
                            {form.formState.errors.keywords && <p className="text-sm text-destructive">{form.formState.errors.keywords.message}</p>}
                            <p className="text-xs text-muted-foreground">Provide comma-separated keywords to guide the AI.</p>
                        </div>
                         <DialogFooter>
                            <DialogClose asChild><Button variant="outline">Cancel</Button></DialogClose>
                            <Button type="submit" disabled={generatePending}>
                                {generatePending && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                                Generate
                            </Button>
                        </DialogFooter>
                    </form>
                ) : (
                    <div className="space-y-4 py-4">
                        <div className="space-y-2">
                            <Label htmlFor="suggestedName">Suggested Name</Label>
                            <Input id="suggestedName" value={generatedContent.suggestedName} onChange={(e) => setGeneratedContent(c => c ? { ...c, suggestedName: e.target.value } : null)} />
                        </div>
                        <div className="space-y-2">
                            <Label htmlFor="description">Generated Description</Label>
                            <Textarea id="description" value={generatedContent.description} rows={6} onChange={(e) => setGeneratedContent(c => c ? { ...c, description: e.target.value } : null)} />
                        </div>
                         <DialogFooter>
                            <Button variant="ghost" onClick={() => setGeneratedContent(null)} disabled={savePending}>Back</Button>
                            <Button onClick={handleSaveChanges} disabled={savePending}>
                                {savePending && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                                Save Changes
                            </Button>
                        </DialogFooter>
                    </div>
                )}
            </DialogContent>
        </Dialog>
    );
}
