

'use client';

import { useState } from 'react';
import type { ReorderSuggestion, CompanyInfo } from '@/types';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { generatePOPdf } from '@/lib/pdf-generator';
import { useToast } from '@/hooks/use-toast';

interface CreatePODialogProps {
  isOpen: boolean;
  onClose: () => void;
  supplierName: string;
  items: ReorderSuggestion[];
  companyInfo: CompanyInfo;
}

export function CreatePODialog({ isOpen, onClose, supplierName, items, companyInfo }: CreatePODialogProps) {
  const { toast } = useToast();
  const [supplierInfo, setSupplierInfo] = useState({
    email: '',
    phone: '',
    address: '',
    notes: ''
  });

  const handleGeneratePO = async () => {
    try {
      await generatePOPdf({
        supplierName,
        supplierInfo,
        items,
        companyInfo,
      });
      toast({
        title: "PO Logged",
        description: "Your purchase order has been logged in the audit trail. PDF generation is temporarily disabled.",
      });
      onClose();
    } catch (error) {
      console.error("Failed to generate PO", error);
      toast({
        variant: "destructive",
        title: "PO Generation Failed",
        description: "Could not log the purchase order.",
      });
    }
  };

  return (
    <Dialog open={isOpen} onOpenChange={onClose}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Create Purchase Order</DialogTitle>
          <DialogDescription>
            Add supplier contact info for <strong>{supplierName}</strong> to generate a PO.
          </DialogDescription>
        </DialogHeader>
        
        <div className="space-y-4 py-4">
          <Input
            placeholder="Supplier Email (for PDF)"
            value={supplierInfo.email}
            onChange={(e) => setSupplierInfo({ ...supplierInfo, email: e.target.value })}
            type="email"
          />
          <Input
            placeholder="Supplier Phone (optional)"
            value={supplierInfo.phone}
            onChange={(e) => setSupplierInfo({ ...supplierInfo, phone: e.target.value })}
          />
          <Textarea
            placeholder="Delivery Address"
            value={supplierInfo.address}
            onChange={(e) => setSupplierInfo({ ...supplierInfo, address: e.target.value })}
          />
          <Textarea
            placeholder="Special instructions (optional)"
            value={supplierInfo.notes}
            onChange={(e) => setSupplierInfo({ ...supplierInfo, notes: e.target.value })}
          />
        </div>
        
        <DialogFooter>
          <Button variant="outline" onClick={onClose}>
            Cancel
          </Button>
          <Button 
            onClick={handleGeneratePO}
            disabled={!supplierInfo.email || !supplierInfo.address}
          >
            Log PO
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

