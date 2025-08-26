import React from 'react';
import clsx from 'clsx';
import Link from '@docusaurus/Link';
import Heading from '@theme/Heading';
import styles from './styles.module.css';

const FeatureList = [
  {
    scale: 0.9,
    title: '.NET',
    Svg: require('@site/static/img/Res_Programming-Language_48_Light.svg').default,
    description: (
      <>
        Learn how to host and maintain your .NET applications on AWS. See how AWS experts deploy and modernize .NET workloads on AWS.
        {/* Guides were designed from the ground up to be easily followed and implemented, getting your cloud monitoring up and running quickly. */}
      </>
    ),
    link: '/DotNET/Guides/',
  },
  {
    scale: 0.8,
    title: 'Active Directory',
    Svg: require('@site/static/img/Res_AWS-Directory-Service_AWS-Managed-Microsoft-AD_48.svg').default,
    description: (
      <>
        Explore Active Directory deployment patterns on AWS for seamless identity management, secure access, and centralized user management.
        {/* Gain comprehensive insights into your AWS environment through key metrics, logs, and performance indicators. */}
      </>
    ),
    link: '/Active Directory/Guides/',
  },
  {
    scale: 0.8,
    title: 'Windows Containers',
    Svg: require('@site/static/img/Res_Amazon-Elastic-Container-Service_Container-2_48.svg').default,
    description: (
      <>
        Innovative techniques and strategies for deploying Windows containers on AWS container services including EKS, ECS and Fargate.
       {/* Streamline your AWS monitoring with purpose-built solutions for efficient data collection, analysis, and visualization. */}
      </>
    ),
    link: '/Windows Containers/Guides/',
  },
  {
    scale: 0.7,
    title: 'SQL Server',
    Svg: require('@site/static/img/Res_Amazon-Aurora-SQL-Server-Instance_48.svg').default,
    description: (
      <>
        Useful insights from experts on effective strategies for running SQL Server on AWS, with practical tips and tricks to enhance performance and scale.
        {/* Implement proven AWS observability patterns to quickly solve common monitoring and troubleshooting challenges. */}
      </>
    ),
    link: '/SQL Server/Guides/',
  },
  {
    scale: 0.7,
    title: 'EC2 Windows',
    Svg: require('@site/static/img/Res_Amazon-EC2_Instance_48.svg').default,
    description: (
      <>
        Guidelines for effectively running Microsoft workloads on Amazon EC2, covering instance types, Image Builder, optimization, and autoscaling.
        {/* Find quick answers to common AWS observability questions, clarifying key concepts and best practices. */}
      </>
    ),
    link: '/EC2 Windows/Guides/',
  },
  {
    scale: 0.6,
    title: 'Licensing',
    Svg: require('@site/static/img/Arch_AWS-License-Manager_64.svg').default,
    description: (
      <>
        Optimize Microsoft licensing and save cost when migrating of your Microsoft workloads to AWS. Find quick answers to common licensing questions.
        {/* Learn step-by-step AWS observability implementation through comprehensive, easy-to-follow instructional resources. */}
      </>
    ),
    link: '/Licensing/Guides/',
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

function Feature({scale, Svg, title, description, link}) {
  return (
    <div className={clsx('col col--4')}>
      <div className="text--center">
        <Link to={link}>
          <Svg transform={"scale(" + scale + ")"} className={styles.featureSvg} role="img" />
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