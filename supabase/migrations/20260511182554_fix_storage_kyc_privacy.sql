-- Fix public exposure of sensitive documents (GDPR / LGPD Compliance)
-- Reverts KYC and vehicle documents buckets from public to private
UPDATE storage.buckets 
SET public = false 
WHERE id IN ('identity-docs', 'documents');

-- Drop public read policies that exposed user documents to the internet
DROP POLICY IF EXISTS "Public access to identity-docs" ON storage.objects;
DROP POLICY IF EXISTS "Leitura Publica Documents" ON storage.objects;

-- Create restricted read policies for identity-docs
-- Allows the owner of the document or an administrator to view the file
CREATE POLICY "Restricted Read identity-docs" 
ON storage.objects 
FOR SELECT 
USING (
  bucket_id = 'identity-docs' 
  AND auth.role() = 'authenticated'
  AND (
    (auth.uid()::text = (storage.foldername(name))[1]) OR
    (auth.uid()::text = (storage.foldername(name))[2]) OR
    (EXISTS (SELECT 1 FROM public.admins WHERE id::text = auth.uid()::text))
  )
);

-- Create restricted read policies for documents
CREATE POLICY "Restricted Read documents" 
ON storage.objects 
FOR SELECT 
USING (
  bucket_id = 'documents' 
  AND auth.role() = 'authenticated'
  AND (
    (auth.uid()::text = (storage.foldername(name))[1]) OR
    (auth.uid()::text = (storage.foldername(name))[2]) OR
    (EXISTS (SELECT 1 FROM public.admins WHERE id::text = auth.uid()::text))
  )
);
