import React from 'react';
import clsx from 'clsx';
import Link from '@docusaurus/Link';
import Heading from '@theme/Heading';
import styles from './styles.module.css';

const FeatureList = [
  {
    title: '.Net',
    Svg: require('@site/static/img/guide.svg').default,
    description: (
      <>
        Learn how to host and maintain your .NET applications.
        {/* Guides were designed from the ground up to be easily followed and implemented, getting your cloud monitoring up and running quickly. */}
      </>
    ),
    link: '/DotNET',
  },
  {
    title: 'Active Directory',
    Svg: require('@site/static/img/signals.svg').default,
    description: (
      <>
        AWS Active Directory environment in AWS.
        {/* Gain comprehensive insights into your AWS environment through key metrics, logs, and performance indicators. */}
      </>
    ),
    link: '/Active-Directory',
  },
  {
    title: 'Windows Containers',
    Svg: require('@site/static/img/tools.svg').default,
    description: (
      <>
        AWS Windows Containers environment in AWS.
       {/* Streamline your AWS monitoring with purpose-built solutions for efficient data collection, analysis, and visualization. */}
      </>
    ),
    link: '/Windows-Containers',
  },
  {
    title: 'SQL Server',
    Svg: require('@site/static/img/recipes.svg').default,
    description: (
      <>
        SQL Server.
        {/* Implement proven AWS observability patterns to quickly solve common monitoring and troubleshooting challenges. */}
      </>
    ),
    link: '/SQL-Server',
  },
  {
    title: 'EC2 Windows',
    Svg: require('@site/static/img/faq.svg').default,
    description: (
      <>
        EC2 Windows.
        {/* Find quick answers to common AWS observability questions, clarifying key concepts and best practices. */}
      </>
    ),
    link: '/EC2-Windows',
  },
  {
    title: 'Licensing',
    Svg: require('@site/static/img/patterns.svg').default,
    description: (
      <>
        Licensing
        {/* Learn step-by-step AWS observability implementation through comprehensive, easy-to-follow instructional resources. */}
      </>
    ),
    link: '/Licensing',
  },
  // {
  //   title: 'CloudOps',
  //   Svg: require('@site/static/img/cloudops.svg').default,
  //   description: (
  //     <>
  //       Learn the AWS Cloud Operations Best Practices.
  //     </>
  //   ),
  //   link: 'https://aws-samples.github.io/cloud-operations-best-practices/',
  // },
];

function Feature({Svg, title, description, link}) {
  return (
    <div className={clsx('col col--4')}>
      <div className="text--center">
        <Link to={link}>
          <Svg className={styles.featureSvg} role="img" />
        </Link>
      </div>
      <div className="text--center padding-horiz--md">
        <Heading as="h3">{title}</Heading>
        <p>{description}</p>
      </div>
    </div>
  );
}

export default function HomepageFeatures() {
  return (
    <section className={styles.features}>
      <div className="container">
        <div className="row">
          {FeatureList.map((props, idx) => (
            <Feature key={idx} {...props} />
          ))}
        </div>
      </div>
    </section>
  );
}