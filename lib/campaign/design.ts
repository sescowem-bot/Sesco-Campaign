import {z} from 'zod';
export const blockSchema=z.discriminatedUnion('type',[
 z.object({type:z.literal('heading'),text:z.string().max(5000)}),
 z.object({type:z.literal('paragraph'),text:z.string().max(5000)}),
 z.object({type:z.literal('button'),text:z.string().max(200),url:z.string().url().startsWith('https://')}),
 z.object({type:z.literal('divider'),text:z.literal('')})
]);
export const designSchema=z.object({version:z.literal('1'),blocks:z.array(blockSchema).max(30)});
export type EmailDesign=z.infer<typeof designSchema>;
export const starterDesign:EmailDesign={version:'1',blocks:[{type:'heading',text:'Hello {{first_name}}'},{type:'paragraph',text:'We have an important update to share with you.'},{type:'button',text:'Learn more',url:'https://example.com'},{type:'divider',text:''}]};
