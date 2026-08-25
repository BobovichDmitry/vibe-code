import api from './index';

export interface BrandingResponse {
  title: string;
  faviconUrl: string;
}

export const getBranding = async (): Promise<BrandingResponse> => {
  const response = await api.get<BrandingResponse>('/api/branding');
  return response.data;
};