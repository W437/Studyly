-- Create storage bucket for scanned images
INSERT INTO storage.buckets (id, name, public)
VALUES ('scans', 'scans', false)
ON CONFLICT (id) DO NOTHING;

-- RLS policy: Users can upload their own scans
CREATE POLICY "Users can upload own scans"
ON storage.objects FOR INSERT
WITH CHECK (
  bucket_id = 'scans'
  AND auth.uid()::text = (storage.foldername(name))[1]
);

-- RLS policy: Users can read their own scans
CREATE POLICY "Users can read own scans"
ON storage.objects FOR SELECT
USING (
  bucket_id = 'scans'
  AND auth.uid()::text = (storage.foldername(name))[1]
);

-- RLS policy: Users can update their own scans
CREATE POLICY "Users can update own scans"
ON storage.objects FOR UPDATE
USING (
  bucket_id = 'scans'
  AND auth.uid()::text = (storage.foldername(name))[1]
);

-- RLS policy: Users can delete their own scans
CREATE POLICY "Users can delete own scans"
ON storage.objects FOR DELETE
USING (
  bucket_id = 'scans'
  AND auth.uid()::text = (storage.foldername(name))[1]
);
