'use client';

import React from 'react';
import { Document, Page, Text, View, StyleSheet } from '@react-pdf/renderer';
import type { PurchaseOrderWithItems, CompanyInfo } from '@/types';

// PDF Styles
const styles = StyleSheet.create({
    page: {
        fontFamily: 'Helvetica',
        fontSize: 11,
        paddingTop: 30,
        paddingLeft: 40,
        paddingRight: 40,
        paddingBottom: 30,
        lineHeight: 1.4,
    },
    header: {
        marginBottom: 20,
        borderBottomWidth: 2,
        borderBottomColor: '#2563EB',
        paddingBottom: 10,
    },
    title: {
        fontSize: 24,
        fontWeight: 'bold',
        color: '#1F2937',
        marginBottom: 5,
    },
    subtitle: {
        fontSize: 12,
        color: '#6B7280',
        marginBottom: 15,
    },
    section: {
        marginBottom: 15,
    },
    sectionTitle: {
        fontSize: 14,
        fontWeight: 'bold',
        color: '#374151',
        marginBottom: 8,
        textTransform: 'uppercase',
    },
    infoGrid: {
        flexDirection: 'row',
        justifyContent: 'space-between',
        marginBottom: 20,
    },
    infoBlock: {
        width: '48%',
    },
    infoLabel: {
        fontSize: 10,
        fontWeight: 'bold',
        color: '#6B7280',
        marginBottom: 3,
    },
    infoValue: {
        fontSize: 11,
        color: '#1F2937',
        marginBottom: 8,
    },
    table: {
        width: '100%',
        marginTop: 15,
    },
    tableHeader: {
        flexDirection: 'row',
        backgroundColor: '#F3F4F6',
        paddingVertical: 8,
        paddingHorizontal: 5,
        borderBottomWidth: 1,
        borderBottomColor: '#D1D5DB',
    },
    tableRow: {
        flexDirection: 'row',
        paddingVertical: 8,
        paddingHorizontal: 5,
        borderBottomWidth: 0.5,
        borderBottomColor: '#E5E7EB',
    },
    tableRowAlt: {
        backgroundColor: '#F9FAFB',
    },
    tableCell: {
        fontSize: 10,
        color: '#374151',
    },
    tableCellHeader: {
        fontSize: 10,
        fontWeight: 'bold',
        color: '#1F2937',
    },
    productCol: { width: '35%' },
    skuCol: { width: '20%' },
    qtyCol: { width: '15%', textAlign: 'center' },
    priceCol: { width: '15%', textAlign: 'right' },
    totalCol: { width: '15%', textAlign: 'right' },
    footer: {
        marginTop: 20,
        paddingTop: 15,
        borderTopWidth: 1,
        borderTopColor: '#E5E7EB',
    },
    totalSection: {
        alignItems: 'flex-end',
        marginTop: 15,
    },
    totalRow: {
        flexDirection: 'row',
        justifyContent: 'space-between',
        width: 200,
        marginBottom: 5,
    },
    totalLabel: {
        fontSize: 11,
        fontWeight: 'bold',
        color: '#374151',
    },
    totalValue: {
        fontSize: 11,
        color: '#1F2937',
    },
    grandTotal: {
        fontSize: 14,
        fontWeight: 'bold',
        color: '#1F2937',
        borderTopWidth: 1,
        borderTopColor: '#D1D5DB',
        paddingTop: 5,
    },
    notes: {
        marginTop: 20,
        padding: 15,
        backgroundColor: '#F9FAFB',
        borderLeftWidth: 3,
        borderLeftColor: '#2563EB',
    },
    notesTitle: {
        fontSize: 12,
        fontWeight: 'bold',
        color: '#1F2937',
        marginBottom: 5,
    },
    notesText: {
        fontSize: 10,
        color: '#6B7280',
        lineHeight: 1.5,
    },
});

interface PurchaseOrderPDFProps {
    purchaseOrder: PurchaseOrderWithItems & { notes?: string | null };
    companyInfo: CompanyInfo & { 
        address?: string | null;
        phone?: string | null;
        email?: string | null;
    };
    supplierName: string;
    supplierInfo: {
        email: string | null;
        phone: string | null;
        notes: string | null;
    };
}

// PDF Document Component
export const PurchaseOrderPDF: React.FC<PurchaseOrderPDFProps> = ({ 
    purchaseOrder, 
    companyInfo, 
    supplierName, 
    supplierInfo 
}) => {
    const formatCurrency = (amount: number) => {
        return new Intl.NumberFormat('en-US', {
            style: 'currency',
            currency: 'USD',
        }).format(amount / 100); // Convert cents to dollars
    };

    const formatDate = (date: string | Date) => {
        return new Date(date).toLocaleDateString('en-US', {
            year: 'numeric',
            month: 'long',
            day: 'numeric',
        });
    };

    const subtotal = purchaseOrder.line_items?.reduce((sum, item) => 
        sum + (item.cost || 0) * (item.quantity || 0), 0) || 0;
    
    const taxAmount = subtotal * 0.08; // 8% tax rate - can be made configurable
    const total = subtotal + taxAmount;

    return (
        <Document>
            <Page size="A4" style={styles.page}>
                {/* Header */}
                <View style={styles.header}>
                    <Text style={styles.title}>Purchase Order</Text>
                    <Text style={styles.subtitle}>
                        Generated on {formatDate(new Date())}
                    </Text>
                </View>

                {/* PO Information */}
                <View style={styles.infoGrid}>
                    <View style={styles.infoBlock}>
                        <Text style={styles.sectionTitle}>Purchase Order Details</Text>
                        <Text style={styles.infoLabel}>PO Number:</Text>
                        <Text style={styles.infoValue}>PO-{purchaseOrder.id}</Text>
                        
                        <Text style={styles.infoLabel}>Status:</Text>
                        <Text style={styles.infoValue}>{purchaseOrder.status}</Text>
                        
                        <Text style={styles.infoLabel}>Order Date:</Text>
                        <Text style={styles.infoValue}>
                            {formatDate(purchaseOrder.created_at)}
                        </Text>
                        
                        {purchaseOrder.expected_arrival_date && (
                            <>
                                <Text style={styles.infoLabel}>Expected Arrival:</Text>
                                <Text style={styles.infoValue}>
                                    {formatDate(purchaseOrder.expected_arrival_date)}
                                </Text>
                            </>
                        )}
                    </View>

                    <View style={styles.infoBlock}>
                        <Text style={styles.sectionTitle}>Supplier Information</Text>
                        <Text style={styles.infoLabel}>Supplier:</Text>
                        <Text style={styles.infoValue}>{supplierName}</Text>
                        
                        {supplierInfo.email && (
                            <>
                                <Text style={styles.infoLabel}>Email:</Text>
                                <Text style={styles.infoValue}>{supplierInfo.email}</Text>
                            </>
                        )}
                        
                        {supplierInfo.phone && (
                            <>
                                <Text style={styles.infoLabel}>Phone:</Text>
                                <Text style={styles.infoValue}>{supplierInfo.phone}</Text>
                            </>
                        )}
                    </View>
                </View>

                {/* Company Information */}
                <View style={styles.section}>
                    <Text style={styles.sectionTitle}>Bill To:</Text>
                    <Text style={styles.infoValue}>{companyInfo.name}</Text>
                    {companyInfo.address && (
                        <Text style={styles.infoValue}>{companyInfo.address}</Text>
                    )}
                    {companyInfo.phone && (
                        <Text style={styles.infoValue}>Phone: {companyInfo.phone}</Text>
                    )}
                    {companyInfo.email && (
                        <Text style={styles.infoValue}>Email: {companyInfo.email}</Text>
                    )}
                </View>

                {/* Line Items Table */}
                <View style={styles.section}>
                    <Text style={styles.sectionTitle}>Order Items</Text>
                    
                    <View style={styles.table}>
                        {/* Table Header */}
                        <View style={styles.tableHeader}>
                            <Text style={[styles.tableCellHeader, styles.productCol]}>Product</Text>
                            <Text style={[styles.tableCellHeader, styles.skuCol]}>SKU</Text>
                            <Text style={[styles.tableCellHeader, styles.qtyCol]}>Qty</Text>
                            <Text style={[styles.tableCellHeader, styles.priceCol]}>Unit Price</Text>
                            <Text style={[styles.tableCellHeader, styles.totalCol]}>Total</Text>
                        </View>

                        {/* Table Rows */}
                        {purchaseOrder.line_items?.map((item, index) => (
                            <View 
                                key={item.id || index} 
                                style={[
                                    styles.tableRow, 
                                    ...(index % 2 === 1 ? [styles.tableRowAlt] : [])
                                ]}
                            >
                                <Text style={[styles.tableCell, styles.productCol]}>
                                    {item.product_name || 'Unknown Product'}
                                </Text>
                                <Text style={[styles.tableCell, styles.skuCol]}>
                                    {item.sku || '-'}
                                </Text>
                                <Text style={[styles.tableCell, styles.qtyCol]}>
                                    {item.quantity || 0}
                                </Text>
                                <Text style={[styles.tableCell, styles.priceCol]}>
                                    {formatCurrency(item.cost || 0)}
                                </Text>
                                <Text style={[styles.tableCell, styles.totalCol]}>
                                    {formatCurrency((item.cost || 0) * (item.quantity || 0))}
                                </Text>
                            </View>
                        ))}
                    </View>
                </View>

                {/* Totals */}
                <View style={styles.totalSection}>
                    <View style={styles.totalRow}>
                        <Text style={styles.totalLabel}>Subtotal:</Text>
                        <Text style={styles.totalValue}>{formatCurrency(subtotal)}</Text>
                    </View>
                    <View style={styles.totalRow}>
                        <Text style={styles.totalLabel}>Tax (8%):</Text>
                        <Text style={styles.totalValue}>{formatCurrency(taxAmount)}</Text>
                    </View>
                    <View style={styles.totalRow}>
                        <Text style={[styles.totalLabel, styles.grandTotal]}>Total:</Text>
                        <Text style={[styles.totalValue, styles.grandTotal]}>
                            {formatCurrency(total)}
                        </Text>
                    </View>
                </View>

                {/* Notes */}
                {purchaseOrder.notes && (
                    <View style={styles.notes}>
                        <Text style={styles.notesTitle}>Notes:</Text>
                        <Text style={styles.notesText}>{purchaseOrder.notes}</Text>
                    </View>
                )}

                {/* Footer */}
                <View style={styles.footer}>
                    <Text style={styles.notesText}>
                        This purchase order is valid for 30 days from the order date. 
                        Please confirm receipt and provide estimated delivery timeline.
                    </Text>
                </View>
            </Page>
        </Document>
    );
};
