/** Pure input validation shared by provider tests and the server. */
export type Provider = 'resend' | 'brevo';
export function domainName(value: string): string {
  const name = value.trim().toLowerCase();
  if (name.length > 253 || !/^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$/.test(name)) {
    throw new Error('Enter a domain such as mail.example.com, without a URL or path.');
  }
  return name;
}
export function mailbox(value: string): string {
  const email = value.trim().toLowerCase();
  if (email.length > 254 || !/^[a-z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-z0-9.-]+$/.test(email)) throw new Error('Enter a valid email address.');
  domainName(email.split('@')[1]);
  return email;
}
export function senderName(value: string): string {
  const name = value.trim();
  if (!name || name.length > 100 || /[\r\n<>]/.test(name)) throw new Error('Enter a sender name of 1 to 100 characters.');
  return name;
}
export function matchesDomain(email: string, domain: string): boolean {
  return mailbox(email).split('@')[1] === domainName(domain);
}
export function escapeHtml(value: string): string {
  return value.replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]!));
}
