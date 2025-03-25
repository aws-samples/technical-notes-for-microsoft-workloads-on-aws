// @ts-check
// `@type` JSDoc annotations allow editor autocompletion and type checking
// (when paired with `@ts-check`).
// There are various equivalent ways to declare your Docusaurus config.
// See: https://docusaurus.io/docs/api/docusaurus-config

import { themes as prismThemes } from 'prism-react-renderer';

// This runs in Node.js - Don't use client-side code here (browser APIs, JSX...)

/** @type {import('@docusaurus/types').Config} */
const config = {
  title: 'Technical notes for Microsoft workloads on AWS',
  tagline: '🖥️ Improve Microsoft workloads on AWS 🚀',
  favicon: 'img/favicon.ico',

  // Set the production url of your site here
  url: 'https://aws-samples.github.io',
  // Set the /<baseUrl>/ pathname under which your site is served
  // For GitHub pages deployment, it is often '/<projectName>/'
  baseUrl: '/', // We need to set '/technical-notes-for-microsoft-workloads-on-aws/' for public repo,

  // GitHub pages deployment config.
  // If you aren't using GitHub pages, you don't need these.
  organizationName: 'aws-samples', // Usually your GitHub org/user name.
  projectName: 'technical-notes-for-microsoft-workloads-on-aws', // Usually your repo name.

  onBrokenLinks: 'warn',
  onBrokenMarkdownLinks: 'warn',

  // Even if you don't use internationalization, you can use this field to set
  // useful metadata like html lang. For example, if your site is Chinese, you
  // may want to replace "en" with "zh-Hans".
  i18n: {
    defaultLocale: 'en',
    locales: ['en'],
  },

  presets: [
    [
      'classic',
      /** @type {import('@docusaurus/preset-classic').Options} */
      ({
        docs: {
          routeBasePath: '/',
          sidebarPath: './sidebars.js',
          // Please change this to your repo.
          // Remove this to remove the "edit this page" links.
          editUrl:
            'https://github.com/aws-samples/technical-notes-for-microsoft-workloads-on-aws/blob/main/docusaurus/',
        },
        theme: {
          customCss: './src/css/custom.css',
        },
      }),
    ],
  ],

  plugins: [

    [
      require.resolve("@easyops-cn/docusaurus-search-local"),
      ({
        //docsDir: "docs",
        hashed: true,
        indexPages: true,
        language: ["en"],
        indexBlog: true,
        indexDocs: true,
      }),
    ],
  ],

  themeConfig:
    /** @type {import('@docusaurus/preset-classic').ThemeConfig} */
    ({
      navbar: {
        title: 'Technical notes for Microsoft workloads on AWS',
        logo: {
          alt: 'AWS Logo',
          src: 'img/logo.svg',
        },
        items: [
          {
            type: 'doc',
            docId: 'home',
            position: 'left',
            label: 'Home',
          },
          {
            type: 'doc',
            docId: 'DotNET/Guides/index',
            position: 'left',
            label: '.NET',
          },
          {
            type: 'doc',
            docId: 'Active-Directory/Guides/index',
            position: 'left',
            label: 'Active Directory',
          },
          {
            type: 'doc',
            docId: 'Windows-Containers/Guides/index',
            position: 'left',
            label: 'Windows Containers',
          },
          {
            type: 'doc',
            docId: 'SQL-Server/Guides/index',
            position: 'left',
            label: 'SQL Server',
          },
          {
            type: 'doc',
            docId: 'EC2-Windows/Guides/index',
            position: 'left',
            label: 'EC2 Windows',
          },
          {
            type: 'doc',
            docId: 'Licensing/Guides/index',
            position: 'left',
            label: 'Licensing',
          },
          // {
          //   type: 'doc',
          //   docId: 'contributors',
          //   position: 'left',
          //   label: 'Contributors',
          // },
          // {
          //   type: 'localeDropdown',
          //   position: 'right',
          // },
          {
            href: 'https://github.com/aws-samples/technical-notes-for-microsoft-workloads-on-aws',
            label: 'GitHub',
            position: 'right',
          },
        ],
      },
      docs: {
        sidebar: {
          hideable: true,
          autoCollapseCategories: true,
        }
      },
      colorMode: {
          defaultMode: 'light',
          disableSwitch: false,
          respectPrefersColorScheme: true,
      },
      footer: {
        style: 'dark',
        copyright: `Built with ❤️ at AWS. <br/> © ${new Date().getFullYear()}.  Amazon.com, Inc. or its affiliates. All Rights Reserved.`,
      },
      prism: {
        theme: prismThemes.github,
        darkTheme: prismThemes.dracula,
      },
    }),
};

export default config;
