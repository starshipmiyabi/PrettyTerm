// Upstream: lobehub/lobehub@00167e7b0f014e640194be732dd251931d663874 (src/styles/sx.ts)

import * as stylex from '@stylexjs/stylex';
import { type CompiledStyles, type InlineStyles, type StyleXArray } from '@stylexjs/stylex';
import { type CSSProperties } from 'react';

type SxStyle = StyleXArray<
  CompiledStyles | boolean | null | undefined | Readonly<[CompiledStyles, InlineStyles]>
>;

type SxArgument = SxStyle | string | CSSProperties;

const isInlineStyle = (argument: SxArgument): argument is CSSProperties =>
  typeof argument === 'object' &&
  argument !== null &&
  !Array.isArray(argument) &&
  !('$$css' in argument);

export const sx = (...args: SxArgument[]) => {
  const styles: SxStyle[] = [];
  const classNames: string[] = [];
  let inline: CSSProperties | undefined;
  for (const argument of args) {
    if (typeof argument === 'string') classNames.push(argument);
    else if (isInlineStyle(argument)) inline = { ...inline, ...argument };
    else styles.push(argument);
  }
  const props = stylex.props(styles);
  const className = [props.className, ...classNames].filter(Boolean).join(' ');
  return {
    className: className || undefined,
    style: props.style || inline ? { ...props.style, ...inline } : undefined,
  };
};
